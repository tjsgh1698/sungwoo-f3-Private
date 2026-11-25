# 성우플라텍 3공장 사출 관제

폰·PC 어디서나 로그인해서 보는 3공장 사이트. MES 설비 현황(보기 전용) + 사출 조건변경 등록/기록.

```
회사 PC (uploader) --10분마다 MES 값만--> Supabase (DB·로그인) <--- 사이트 (Netlify, site/)
       │ 읽기 전용                                              조건변경: 등록만 가능
   MES DB (MS SQL, 사내)                                        MES 값: 보기만 가능
```

## 폴더
- `site/index.html` 사이트 전체(한 파일). `CFG.sb` 에 Supabase 주소·공개키.
- `uploader/` 회사 PC에서 도는 MES → Supabase 업로더. 조회문은 `mes.sql`.
- `supabase/schema.sql` DB 표와 권한(RLS).

## 배포
- 사이트: Netlify가 이 저장소 main 브랜치를 자동 배포 (`netlify.toml`, publish = site).
- 업로더(회사 PC, Node 18+): `cd uploader && npm i` 후 환경변수
  `MES_SERVER MES_PORT MES_DB MES_USER MES_PW MES_PLANT SB_URL SB_SERVICE_KEY` 설정 → `npm start`.
  service_role 키와 MES 비밀번호는 저장소에 절대 넣지 않음.

## 계정
- 로그인 아이디 `0121` = Supabase 사용자 `0121@sungwoo-f3.local`. 신규 가입은 막혀 있음(관리자가 Supabase에서 추가).

## 회사 PC 업로더 (Node 불필요)
uploader 폴더를 PC에 두고 env.example 을 .env 로 복사해 값 입력 → `powershell -ExecutionPolicy Bypass -File uploader.ps1 -Dry` 로 시험 → install-task.bat 으로 10분마다 자동 실행.
MES DB 접속정보는 MES 프로그램 안에 암호화돼 있어 IT/SWIT 에서 읽기 전용 계정을 받아야 함.
