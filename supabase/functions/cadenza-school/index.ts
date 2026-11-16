import postgres from "postgres";

const sql = postgres(Deno.env.get("SUPABASE_DB_URL")!, { prepare: false, max: 1, idle_timeout: 10 });
const headers = { "Content-Type": "application/json", "Cache-Control": "no-store" };
const reply = (status: number, error: string) => new Response(JSON.stringify({ error }), { status, headers });

// Tokens, email addresses, rows and upstream errors are never logged.
Deno.serve(async (request: Request) => {
  if (request.method !== "GET") return reply(405, "method_not_allowed");
  const authorization = request.headers.get("Authorization") ?? "";
  if (!/^Bearer [A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(authorization)) return reply(401, "authentication_required");
  try {
    const response = await fetch(`${Deno.env.get("SUPABASE_URL")}/auth/v1/user`, {
      headers: { Authorization: authorization, apikey: Deno.env.get("SUPABASE_ANON_KEY")! },
    });
    if (!response.ok) return reply(401, "invalid_session");
    const user = await response.json();
    if (!user.id || !user.email || !user.email_confirmed_at || user.is_anonymous === true) return reply(403, "reader_not_authorized");
    const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(user.email.trim().toLowerCase())));
    const emailHash = [...digest].map(value => value.toString(16).padStart(2, "0")).join("");
    const encoded = authorization.slice(7).split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
    const claims = JSON.parse(atob(encoded.padEnd(Math.ceil(encoded.length / 4) * 4, "=")));
    if (claims.sub !== user.id || typeof claims.session_id !== "string" || !/^[0-9a-f-]{36}$/i.test(claims.session_id)) return reply(401, "invalid_session");

    const result = await sql.begin("read only", async tx => {
      await tx`set local statement_timeout = '8000ms'`;
      const authorized = await tx`
        select 1 from cadenza_private.reader_access a
        join auth.sessions s on s.user_id = ${user.id}::uuid and s.id = ${claims.session_id}::uuid
        where a.email_sha256 = ${emailHash} and a.enabled
          and (a.user_id is null or a.user_id = s.user_id)
          and (s.not_after is null or s.not_after > now()) limit 1`;
      if (!authorized.length) return null;
      // One MVCC snapshot; no PRONOTE request and no changes to the sync jobs.
      const rows = await tx`
        with bounds as (
          select (now() at time zone 'Europe/Paris')::date - 90 as first_day,
                 (now() at time zone 'Europe/Paris')::date + 121 as last_day
        ) select jsonb_build_object(
          'generated_at', now(),
          'window_start', (select first_day::timestamp at time zone 'Europe/Paris' from bounds),
          'window_end', (select last_day::timestamp at time zone 'Europe/Paris' from bounds),
          'timetable', coalesce((select jsonb_agg(jsonb_build_object(
            'event_id',e.event_id,'start_local',e.start_local::text,'end_local',e.end_local::text,
            'start_at',e.start_local at time zone 'Europe/Paris','end_at',e.end_local at time zone 'Europe/Paris',
            'subject_id',e.subject_id,'subject_name',e.subject_name,'teacher_names',e.teacher_names,
            'classrooms',e.classrooms,'group_names',e.group_names,'canceled',e.canceled,
            'exempted',e.exempted,'is_test',e.is_test,'lesson_resource_id',e.lesson_resource_id)
            order by e.start_local,e.event_id) from pronote_private.timetable_event e,bounds w
            where e.start_local >= w.first_day and e.start_local < w.last_day),'[]'::jsonb),
          'homework',coalesce((select jsonb_agg(jsonb_build_object(
            'uid',h.uid,'pronote_id',h.pronote_id,'subject',h.subject,'deadline',h.deadline,
            'description',h.description,'done',h.done,'difficulty',h.difficulty,'length_minutes',h.length_minutes,
            'attachment_names',h.attachment_names,'external_links',h.external_links,
            'source_updated_at',h.source_updated_at,'synced_at',h.synced_at) order by h.deadline,h.uid)
            from pronote_private.homework h),'[]'::jsonb),
          'course_content',coalesce((select jsonb_agg(jsonb_build_object(
            'resource_id',c.resource_id,'content_id',c.content_id,'title',c.title,'description',c.description,
            'category',c.category,'category_text',c.category_text,'files',c.files,'themes',c.themes,
            'external_links',c.external_links,'source_updated_at',c.source_updated_at,'synced_at',c.synced_at)
            order by c.resource_id,c.content_id) from pronote_private.course_content c),'[]'::jsonb),
          'sync_state',jsonb_build_object(
            'last_timetable_sync',(select max(synced_at) from pronote_private.timetable_event),
            'last_homework_sync',(select max(synced_at) from pronote_private.homework),
            'last_content_sync',(select max(synced_at) from pronote_private.course_content),
            'has_error',(select last_error is not null or last_course_error is not null from pronote_private.sync_state where id=1))) as snapshot`;
      return rows[0].snapshot;
    });
    if (!result) return reply(403, "reader_not_authorized");
    const body = JSON.stringify(result);
    if (body.length > 8_000_000) return reply(503, "snapshot_too_large");
    return new Response(body, { status: 200, headers });
  } catch {
    return reply(503, "school_temporarily_unavailable");
  }
});
