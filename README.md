# Memo4Me

macOS 메뉴바 전용 메모지 앱입니다(저장소 이름 `memo-for-me`). 데스크톱의 특정 화면(Space)에 메모를 붙여 두고 쓰며, 일반 메모는 `.md` 파일로, 보안 메모는 암호화해서 저장합니다.

이 앱은 Notion도 Claude도 모릅니다. 메모를 **정해진 규격의 폴더**에 남길 뿐이고, 그 폴더를 읽어 Notion 등으로 연결하는 일은 별도 프로그램 [`sticky`](../notion-memo-agent)가 합니다.

## 기능
- 노랑/파랑 메모지, 이미지 배경, 둥근 모서리, 모서리·변 핸들로 크기 조절
- 선택한 글자에만 크기·굵게·기울임·밑줄·취소선 적용(플로팅 서식 바)
- 상단 바: 닫기 · 고정 · 최상단 고정 · 색 · 삭제 · 이름 · 새 메모
- 메뉴바 항목: 메모지 추가 / 목록 / 설정 / 종료 (독 아이콘 없음)
- 메모지는 만들어진 Space에 붙고, 재실행하면 열려 있던 메모를 위치·크기·색과 함께 복원
- 보안 메모: AES-256-GCM 암호화 + Touch ID/암호 잠금, 폴더와 변경 기록에는 나타나지 않음
- 한글 입력 상태에서도 동작하는 단축키: `⌘N` `⌘W` `⌘B/I/U` `⌘+/-` `⌘⇧X` `⌘C/V/X/A/Z`

## 구성
```
App/                 AppKit/SwiftUI 앱 본체 (창, 편집기, 상단 바, 서식 바, 설정)
Sources/StickyCore/  UI와 무관한 핵심 로직 (SwiftPM 패키지: 저장, 변환, 암호화, 폴더 접근)
Tests/               StickyCore 단위 테스트
project.yml          XcodeGen 설정 (.xcodeproj는 생성물이라 git에서 제외)
scripts/             앱 아이콘 생성
docs/DESIGN.md       설계서
```

## 빌드와 실행
필요한 것: Xcode 26, [XcodeGen](https://github.com/yonaskolb/XcodeGen), macOS 14 이상.

```bash
swift test                                   # StickyCore 테스트
xcodegen generate                            # Memo4Me.xcodeproj 생성
xcodebuild -scheme Memo4Me -configuration Debug -destination 'platform=macOS' build
```

빌드된 앱은 `~/Library/Developer/Xcode/DerivedData/Memo4Me-*/Build/Products/Debug/Memo4Me.app`에 만들어집니다. 앱 이름은 "Memo4Me", 번들 ID는 `com.kimerz.memo-for-me`입니다.

## 메모 폴더 (연결 규격)
설정에서 고른 폴더에 아래를 남깁니다. 규격 전체는 `sticky` 저장소의 `docs/NOTE-APP-INTEGRATION-GUIDE.md`(Notes Source Contract v1)에 있습니다.

| 파일 | 내용 |
|---|---|
| `<제목>-<짧은id>.md` | 메모 1개. 앞머리에 `id`, `created`, `type: note`, (선택) `name` |
| `changes.jsonl` | 생성/수정/삭제를 한 줄씩 추가(`v`, `ts`, `event`, `id`, `file`, `title`). 본문은 없음 |
| `sticky-source.json` | 이 폴더가 규격을 지킨다는 표시 |

샌드박스 앱은 폴더를 북마크로만 기억해서 다른 프로그램이 경로를 알 수 없으므로, 앱 컨테이너에 실제 경로를 `notes-folder.txt`로 적어 둡니다. 설정 화면에 "경로 복사" 버튼도 있습니다.
