-- F3 Camera/Feed: posts storage bucket + create_post RPC
-- The client uploads {post_id}/front.jpg and {post_id}/back.jpg into the
-- "posts" bucket, then calls create_post() which writes the row atomically
-- (RLS-checked group membership, author_id = auth.uid()).

-- ============================================================
-- STORAGE BUCKET
-- ============================================================

INSERT INTO storage.buckets (id, name, public)
VALUES ('posts', 'posts', false)
ON CONFLICT (id) DO NOTHING;

-- ============================================================
-- STORAGE RLS — posts bucket
-- ============================================================

CREATE POLICY posts_storage_insert
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'posts'
    AND owner = auth.uid()
  );

-- A group member can read any object referenced by a (non-deleted) post in
-- their group. Using front/back path equality keeps the policy simple and
-- avoids fragile path parsing.
CREATE POLICY posts_storage_select
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'posts'
    AND EXISTS (
      SELECT 1 FROM public.posts p
      WHERE (p.front_image_path = name OR p.back_image_path = name)
        AND public.is_group_member(p.group_id)
        AND p.deleted_at IS NULL
    )
  );

CREATE POLICY posts_storage_delete
  ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'posts'
    AND owner = auth.uid()
  );

-- ============================================================
-- RPC — atomic post creation
-- ============================================================

CREATE OR REPLACE FUNCTION public.create_post(
  p_post_id      UUID,
  p_group_id     UUID,
  p_front_path   TEXT,
  p_back_path    TEXT,
  p_caption      TEXT,
  p_prompt_date  DATE
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NOT public.is_group_member(p_group_id) THEN
    RAISE EXCEPTION 'Not a group member';
  END IF;

  INSERT INTO public.posts (
    id, group_id, author_id, kind,
    front_image_path, back_image_path, caption,
    prompt_date, prompt_time, posted_at
  ) VALUES (
    p_post_id, p_group_id, auth.uid(), 'dual_photo',
    p_front_path, p_back_path, NULLIF(p_caption, ''),
    p_prompt_date, NOW(), NOW()
  );

  RETURN p_post_id;
END $$;
