-- spec/06: leap-year edge case. Original get_memories only matched on the
-- exact MM-DD; users active on Feb 28 in non-leap years would lose every
-- memory from Feb 29 in past leap years. Spec calls for that day to inherit
-- those memories so the archive doesn't have a 4-year-cycle dead zone.
--
-- We detect "today is Feb 28 in a non-leap year" by checking whether
-- (today + 1 day) lands on March 1; if so, also include matches on Feb 29.

CREATE OR REPLACE FUNCTION public.get_memories(p_group_id UUID, p_today DATE DEFAULT CURRENT_DATE)
RETURNS TABLE (
  post_id UUID,
  prompt_date DATE,
  years_ago INTEGER,
  author_name TEXT,
  front_image_path TEXT,
  back_image_path TEXT,
  caption TEXT
) LANGUAGE SQL SECURITY DEFINER STABLE
SET search_path = public, pg_temp AS $$
  SELECT
    p.id,
    p.prompt_date,
    EXTRACT(YEAR FROM AGE(p_today, p.prompt_date))::INT AS years_ago,
    u.display_name,
    p.front_image_path,
    p.back_image_path,
    p.caption
  FROM public.posts p
  JOIN public.users u ON u.id = p.author_id
  WHERE p.group_id = p_group_id
    AND p.deleted_at IS NULL
    AND public.is_group_member(p.group_id)
    AND p.prompt_date < p_today
    AND (
      -- Same MM-DD as today.
      (
        EXTRACT(MONTH FROM p.prompt_date) = EXTRACT(MONTH FROM p_today)
        AND EXTRACT(DAY FROM p.prompt_date) = EXTRACT(DAY FROM p_today)
      )
      OR
      -- Feb 29 spillover: today is Feb 28 in a non-leap year (the next day
      -- is March 1) — surface past Feb 29 memories so they don't vanish for
      -- three out of every four years.
      (
        EXTRACT(MONTH FROM p_today) = 2
        AND EXTRACT(DAY FROM p_today) = 28
        AND EXTRACT(MONTH FROM (p_today + INTERVAL '1 day')) = 3
        AND EXTRACT(MONTH FROM p.prompt_date) = 2
        AND EXTRACT(DAY FROM p.prompt_date) = 29
      )
    )
  ORDER BY p.prompt_date DESC;
$$;
