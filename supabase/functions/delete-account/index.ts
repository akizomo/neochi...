// アカウントの削除(アプリの「アカウントを削除」から呼ぶ)。App Store の審査で、アプリ内からの削除が求められる。
// 呼び出した本人の JWT を確かめ、本人の記録(sleep_log)と auth のユーザーを消す。service role はこの関数の中だけで使う。
// デプロイ: supabase functions deploy delete-account(JWT の検証は関数の中で行う)
import { createClient } from "npm:@supabase/supabase-js@2";

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("method not allowed", { status: 405 });
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer /i, "");
  if (!token) return new Response("unauthorized", { status: 401 });

  const url = Deno.env.get("SUPABASE_URL")!;
  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

  const { data, error } = await admin.auth.getUser(token);
  if (error || !data.user) return new Response("unauthorized", { status: 401 });
  const uid = data.user.id;

  const del = await admin.from("sleep_log").delete().eq("user_id", uid);
  if (del.error) return new Response("failed to delete records", { status: 500 });
  const res = await admin.auth.admin.deleteUser(uid);
  if (res.error) return new Response("failed to delete user", { status: 500 });
  return new Response(null, { status: 204 });
});
