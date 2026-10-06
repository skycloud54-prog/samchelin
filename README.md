# 삼슐랭 가이드 · 무료 배포 데모

2026 DISCOVER B-2조(삼슐랭) 과제 앱이에요. 신입 회계사가 현장 근처 맛집을 등록·공유·추천해요.

## 폴더 구성

| 파일 | 역할 |
|---|---|
| `index.html` | 앱 화면 전체 (S01 홈 · S02 등록 · S03 찾기 · S04 족보 커뮤니티 · S05 전체 맛집) |
| `api/config.js` | Vercel 환경변수에서 **공개용 키만** 꺼내 앱에 전달 (비밀키가 들어오면 막음) |
| `vendor/supabase.js` | Supabase 연결 도구 (supabase-js 2.117.2, MIT) |
| `vercel.json` | 보안 헤더 설정 |
| `supabase_schema.sql` | Supabase 표·규칙 (SQL Editor에서 이미 실행함) |

## Vercel 환경변수 (Settings → Environment Variables)

| 이름 | 값 |
|---|---|
| `SUPABASE_URL` | Supabase Project URL (`https://xxxx.supabase.co`) |
| `SUPABASE_KEY` | Supabase **Publishable key** 또는 **anon public** 키 (secret/service_role 금지) |
| `KAKAO_JS_KEY` | 카카오 **JavaScript 키** (REST/Admin 키 금지) |

키는 이 저장소(GitHub)에 넣지 않아요.

## 데이터 원칙

- `[가상]`이 붙은 식당 58곳과 그 추천·팁은 샘플데이터 v3의 가상 값이에요.
- 사용자가 등록한 식당의 장소 정보는 카카오맵에서 가져와요(출처 표시).
- 로그인이 없어서 브라우저별 익명 ID로 하루 1회 추천을 구분해요(O3).
- 실명, 연락처, 고객사 정보는 입력하지 않아요.

## 기준

- 디자인: design.md v1.2 · 문구: 개발 인계 문서 10.04 개정 · TOP 3: 매일 18:00(KST) 기준 직전 72시간 추천 수
