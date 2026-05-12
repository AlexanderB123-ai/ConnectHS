import Foundation
import Supabase
import PostgREST
import Storage

/// The narrow surface the view models actually call. Extracted so VM tests
/// can inject a stub without standing up a real Supabase client. The full
/// `PostService` struct conforms; production call sites are unaffected.
protocol PostServicing: Sendable {
    func getFeed(groupId: UUID, date: Date) async throws -> [FeedPost]
    func getMemories(groupId: UUID) async throws -> [MemoryPost]
    func toggleReaction(postId: UUID, reaction: ReactionType) async throws -> Bool
    func markViewed(postId: UUID) async throws
    func myReactions(postId: UUID, userId: UUID) async throws -> Set<ReactionType>
}

extension PostServicing {
    /// Convenience overload so call sites can keep using `getFeed(groupId:)`
    /// without explicitly threading `Date()` through. Protocol-level default
    /// arguments aren't dispatched, so we provide it as an extension.
    func getFeed(groupId: UUID) async throws -> [FeedPost] {
        try await getFeed(groupId: groupId, date: Date())
    }
}

struct PostService: Sendable, PostServicing {

    nonisolated static let postsBucket = "posts"

    /// Upload front+back JPEGs and atomically create the post row via RPC.
    /// The unique-per-day index on (group_id, author_id, prompt_date) is the canonical
    /// guard against double-posting; we surface the Postgres error as `alreadyPostedToday`.
    func uploadMoment(
        postId: UUID,
        groupId: UUID,
        frontJpeg: Data,
        backJpeg: Data,
        caption: String?
    ) async throws {
        let frontPath = "\(postId.uuidString)/front.jpg"
        let backPath = "\(postId.uuidString)/back.jpg"

        async let frontUpload = supabase.storage
            .from(Self.postsBucket)
            .upload(frontPath, data: frontJpeg, options: .init(contentType: "image/jpeg"))
        async let backUpload = supabase.storage
            .from(Self.postsBucket)
            .upload(backPath, data: backJpeg, options: .init(contentType: "image/jpeg"))
        _ = try await (frontUpload, backUpload)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        let promptDate = formatter.string(from: Date())

        let params: [String: String] = [
            "p_post_id": postId.uuidString,
            "p_group_id": groupId.uuidString,
            "p_front_path": frontPath,
            "p_back_path": backPath,
            "p_caption": caption ?? "",
            "p_prompt_date": promptDate
        ]
        try await supabase.rpc("create_post", params: params).execute()
    }

    /// Generate a short-lived signed URL for an image path stored in the `posts` bucket.
    func signedURL(forImagePath path: String, expiresIn seconds: Int = 6 * 3600) async throws -> URL {
        try await supabase.storage
            .from(Self.postsBucket)
            .createSignedURL(path: path, expiresIn: seconds)
    }

    func getFeed(groupId: UUID, date: Date = Date()) async throws -> [FeedPost] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: date)

        return try await supabase
            .rpc("get_feed", params: [
                "p_group_id": groupId.uuidString,
                "p_date": dateString
            ])
            .execute()
            .value
    }

    /// Fetch a single post by id (deep-link hydration). Returns nil when the
    /// caller isn't a member of the post's group (RLS yields zero rows) or
    /// when the post has been soft-deleted.
    func getPost(id: UUID) async throws -> DeepLinkedPost? {
        let rows: [DeepLinkedPost] = try await supabase
            .rpc("get_post", params: [
                "p_post_id": id.uuidString
            ])
            .execute()
            .value
        return rows.first
    }

    func getMemories(groupId: UUID) async throws -> [MemoryPost] {
        try await supabase
            .rpc("get_memories", params: [
                "p_group_id": groupId.uuidString
            ])
            .execute()
            .value
    }

    /// Page through the permanent archive. `before` is the strictly-older
    /// upper bound (exclusive) — pass the smallest `promptDate` you've already
    /// loaded, or nil for the first page.
    func getArchive(
        groupId: UUID,
        before: String? = nil,
        limit: Int = 60,
        onlyMine: Bool = false
    ) async throws -> [ArchivePost] {
        struct Params: Encodable {
            let p_group_id: String
            let p_before: String?
            let p_limit: Int
            let p_only_mine: Bool
        }
        let params = Params(
            p_group_id: groupId.uuidString,
            p_before: before,
            p_limit: limit,
            p_only_mine: onlyMine
        )
        return try await supabase
            .rpc("get_archive", params: params)
            .execute()
            .value
    }

    func toggleReaction(postId: UUID, reaction: ReactionType) async throws -> Bool {
        try await supabase
            .rpc("toggle_reaction", params: [
                "p_post_id": postId.uuidString,
                "p_reaction": reaction.rawValue
            ])
            .execute()
            .value
    }

    func markViewed(postId: UUID) async throws {
        try await supabase
            .rpc("mark_viewed", params: [
                "p_post_id": postId.uuidString
            ])
            .execute()
    }

    /// Reactions the current authenticated user has applied to a post.
    /// RLS already restricts visibility to group members, so we just filter by user_id.
    func myReactions(postId: UUID, userId: UUID) async throws -> Set<ReactionType> {
        let rows: [Reaction] = try await supabase
            .from("reactions")
            .select()
            .eq("post_id", value: postId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value
        return Set(rows.map(\.reaction))
    }

    /// Joined reactor list for a single emoji on a post — used by the
    /// long-press affordance in PostDetailView's reaction bar.
    func listReactors(postId: UUID, reaction: ReactionType) async throws -> [PostReactor] {
        try await supabase
            .rpc("list_post_reactors", params: [
                "p_post_id": postId.uuidString,
                "p_reaction": reaction.rawValue
            ])
            .execute()
            .value
    }
}
