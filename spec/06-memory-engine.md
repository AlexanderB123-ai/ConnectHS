# 06 — Memory Engine (F5)

The compound-interest feature. Every day, surface "X year(s) ago today" content from each group's archive. This is what BeReal failed to harvest and why ConnectHS retains.

## Goals
- The longer a group is on ConnectHS, the more valuable it gets
- Daily memory push has > 30% open rate
- Resurfaces are emotionally meaningful (real shared moments, not isolated solo posts)

## Core mechanic

Every day at 09:00 user-local time, for each user, for each group:
1. Query `get_memories(group_id, today)` — finds posts from prior years on today's MM-DD
2. If non-empty, send a push notification
3. User taps push → `connecths://memory/{post_id}` → `MemoryDetailView`

## SQL query (already defined in 02-data-model.md)

```sql
CREATE OR REPLACE FUNCTION public.get_memories(p_group_id UUID, p_today DATE DEFAULT CURRENT_DATE)
RETURNS TABLE (
  post_id UUID, prompt_date DATE, years_ago INTEGER,
  author_name TEXT, front_image_path TEXT, back_image_path TEXT, caption TEXT
) LANGUAGE SQL SECURITY DEFINER STABLE AS $$
  SELECT p.id, p.prompt_date,
    EXTRACT(YEAR FROM AGE(p_today, p.prompt_date))::INT,
    u.display_name, p.front_image_path, p.back_image_path, p.caption
  FROM public.posts p
  JOIN public.users u ON u.id = p.author_id
  WHERE p.group_id = p_group_id
    AND EXTRACT(MONTH FROM p.prompt_date) = EXTRACT(MONTH FROM p_today)
    AND EXTRACT(DAY FROM p.prompt_date)   = EXTRACT(DAY FROM p_today)
    AND p.prompt_date < p_today
    AND p.deleted_at IS NULL AND public.is_group_member(p.group_id)
  ORDER BY p.prompt_date DESC;
$$;
```

## Edge Function: `memory-engine`

Cron schedule: every hour, for each timezone whose local time is 09:00.

```typescript
// supabase/functions/memory-engine/index.ts
import { serve } from "https://deno.land/std/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

serve(async (req) => {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  )

  // Find users in timezones where it's currently 09:00
  const { data: users } = await supabase
    .from("users")
    .select("id, timezone, display_name")
    .is("deleted_at", null)
    // ... filter to current 09:00-window users

  for (const user of users) {
    // Check notification settings
    const { data: settings } = await supabase
      .from("notification_settings")
      .select("memory_enabled")
      .eq("user_id", user.id)
      .single()

    if (!settings?.memory_enabled) continue

    // Get user's groups
    const { data: memberships } = await supabase
      .from("group_memberships")
      .select("group_id")
      .eq("user_id", user.id)
      .is("left_at", null)

    for (const m of memberships ?? []) {
      const { data: memories } = await supabase.rpc("get_memories", {
        p_group_id: m.group_id,
        p_today: new Date().toISOString().slice(0, 10),
      })

      if (!memories || memories.length === 0) continue

      const top = memories[0]  // most recent / closest year
      const others = memories.length > 1 ? `+${memories.length - 1} more` : ""

      await invokeFunction("send-push", {
        user_id: user.id,
        title: `📸 memory from ${top.years_ago}yr ago`,
        body: top.caption ?? `you and ${top.author_name} ${others}`,
        deep_link: `connecths://memory/${top.post_id}`,
        thread_id: `memory-${m.group_id}`,
      })
    }
  }

  return new Response("ok")
})
```

## Memory Detail screen

```swift
struct MemoryDetailView: View {
    let postID: UUID
    @State private var memories: [Memory] = []  // could be multiple years on same date

    var body: some View {
        VStack {
            // Hero: full-screen carousel of past moments
            TabView {
                ForEach(memories) { memory in
                    MemoryCardView(memory: memory)
                }
            }
            .tabViewStyle(.page)

            // Title + subtitle
            Text("\(yearsAgo) year(s) ago today")
                .font(.title)
            Text("\(memory.authorName) in \(groupName)")

            // Share to IG Stories button
            Button("share") { exportToInstagramStories() }
        }
    }
}
```

### Layout

```
┌─────────────────────────────────────┐
│                                     │
│         [past photo, full]          │
│                       ┌──────┐      │
│                       │front │      │
│                       └──────┘      │
│              ◀  ●○○  ▶              │  ← carousel dots
├─────────────────────────────────────┤
│       1 year ago today              │
│   sarah · the boys                  │
│   "graduation day 🎓"               │
│                                     │
│         [  share  ]                 │
└─────────────────────────────────────┘
```

## Memory ribbon (in feed)

Small horizontal card at top of `FeedView` if any memories exist for today:

```
┌─────────────────────────────────────┐
│ 📸 1 year ago today  >              │
└─────────────────────────────────────┘
```

Tap → `MemoryDetailView`.

## Share to Instagram Stories

When user taps "share":
1. Render a 1080x1920 image with:
   - The back image as background
   - Front image as inset
   - Bottom text: `"X year ago today · made on connecths"`
2. Use `UIActivityViewController` with `IGSharedItem` (Instagram's documented Stories share format)
3. Falls back to standard share sheet for other apps

## Edge cases

- **Leap day (Feb 29):** if today is Feb 28 in non-leap year, also surface Feb 29 from prior leap years
- **Multiple memories same day:** carousel shows newest first
- **User joined group recently:** if user wasn't a member when post was made, RLS should block — verify `is_group_member` returns true. Memories ARE viewable to all current members, even those who joined after the post (this is intentional — they're now part of the group's history).
- **Author left group:** post still visible (author shown by historical name)

## Acceptance criteria

- [ ] `get_memories` RPC returns correct results for a group with posts on prior years' same MM-DD
- [ ] `memory-engine` Edge Function runs daily at 09:00 user-local
- [ ] Push notification dispatched when memories exist
- [ ] No push sent if `notification_settings.memory_enabled = false`
- [ ] Tapping push opens `MemoryDetailView` with correct post pre-loaded
- [ ] Memory ribbon appears in feed when today has past-year content
- [ ] Carousel shows multiple memories from different years
- [ ] Share-to-IG renders correct 1080x1920 image
- [ ] Test: insert a post with `prompt_date = (today - 1 year)`, verify next morning's push fires
- [ ] Test: leap year edge case (Feb 29 / Feb 28 handling)
