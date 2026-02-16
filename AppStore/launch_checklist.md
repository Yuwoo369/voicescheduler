# VoiceScheduler 런치 체크리스트

## 🎨 에셋 준비
- [x] 앱 아이콘 (모든 사이즈)
- [x] 스플래시 스크린
- [x] App Store 스크린샷 (6.7", 6.5")
- [ ] App Preview 동영상 (선택사항)

## 📝 메타데이터
- [x] 앱 이름 (7개 언어)
- [x] 부제목 (7개 언어)
- [x] 키워드 (7개 언어)
- [x] 설명 (7개 언어)
- [x] 버전 노트

## 📄 법적 문서
- [x] 개인정보 처리방침 (HTML)
- [x] 이용약관 (HTML)
- [x] 웹사이트 준비 완료

## 🌐 웹 페이지
- [x] 랜딩 페이지 (index.html)
- [x] 지원/FAQ 페이지 (support.html)
- [x] Privacy Policy (privacy.html)
- [x] Terms of Service (terms.html)
- [ ] GitHub Pages 배포 (개발자 등록 후)

## 🌍 다국어 지원
- [x] 한국어 (ko)
- [x] English (en)
- [x] 日本語 (ja)
- [x] 简体中文 (zh-Hans)
- [x] 繁體中文 (zh-Hant) ✨ NEW
- [x] Español (es)
- [x] Français (fr) ✨ NEW
- [x] 권한 설명 문구 (7개 언어)

## ⚙️ 프로젝트 설정
- [x] 버전 번호: 1.0
- [x] 빌드 번호: 1
- [x] Bundle ID: com.taeseok.voicescheduler2026
- [x] 최소 iOS 버전: 17.0
- [x] 권한 설명 문구 (InfoPlist.strings)

## 🔧 앱 품질 (테스트 필요)
- [ ] 전체 기능 테스트
- [ ] 7개 언어 UI 테스트
- [ ] 위젯 테스트
- [ ] 다크모드 테스트
- [ ] 다양한 기기 크기 테스트
- [ ] 메모리 누수 체크
- [ ] 크래시 테스트
- [ ] 엣지 케이스 테스트

## 📱 최종 테스트 (테스트 필요)
- [ ] 실제 기기 전체 플로우 테스트
- [ ] Google 로그인 테스트
- [ ] 캘린더 등록 테스트
- [ ] 음성 인식 테스트
- [ ] 스마트 타임 슬롯 테스트
- [ ] 다국어 전환 테스트

---

## 📁 파일 구조

```
AppStore/
├── metadata.md          # App Store 메타데이터
├── launch_checklist.md  # 이 파일
├── Screenshots/
│   ├── 6.7/            # iPhone 15 Pro Max
│   └── 6.5/            # iPhone 14 Plus
└── website/
    ├── index.html      # 랜딩 페이지
    ├── privacy.html    # 개인정보 처리방침
    ├── terms.html      # 이용약관
    ├── support.html    # 지원/FAQ
    └── icon.png        # 앱 아이콘
```

## 🚀 개발자 등록 후 할 일

1. **GitHub Pages 배포**
   - Repository 생성: voicescheduler.github.io
   - website/ 폴더 내용 업로드
   - Custom domain 설정: voicescheduler.app

2. **App Store Connect**
   - 앱 생성
   - 메타데이터 입력
   - 스크린샷 업로드
   - 빌드 업로드 (Archive)

3. **심사 제출**
   - 앱 심사 정보 입력
   - 제출
