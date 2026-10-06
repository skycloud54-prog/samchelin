// 삼슐랭 가이드 · 공개 설정 전달 (Vercel 서버리스 함수)
// 키는 코드·GitHub에 없고, Vercel 환경변수에만 있어요.
// 여기서 내보내는 값은 전부 "공개용" 키예요. 비밀키가 잘못 들어오면 내보내지 않아요.
function isSecret(key) {
  if (!key) return false;
  if (key.startsWith("sb_secret_")) return true;
  const parts = key.split(".");
  if (parts.length === 3) {
    try {
      const payload = JSON.parse(Buffer.from(parts[1], "base64").toString("utf8"));
      if (payload.role === "service_role") return true;
    } catch (e) {}
  }
  return false;
}

module.exports = (req, res) => {
  const supabaseUrl = process.env.SUPABASE_URL || "";
  let supabaseKey = process.env.SUPABASE_KEY || "";
  const kakaoKey = process.env.KAKAO_JS_KEY || "";
  if (isSecret(supabaseKey)) {
    console.error("SUPABASE_KEY에 비밀키(secret/service_role)가 들어 있어요. 공개키(publishable/anon)로 바꿔주세요.");
    supabaseKey = "";
  }
  res.setHeader("Content-Type", "application/json; charset=utf-8");
  res.setHeader("Cache-Control", "public, max-age=300");
  res.status(200).send(JSON.stringify({ supabaseUrl, supabaseKey, kakaoKey }));
};
