# REPORT-001: 프로젝트 구조 파악

**task**: TASK-001  
**date**: 2026-06-23

---

## 프로젝트 한 줄 정의

`kknaks_profile`은 이건학(kknaks)의 페르소나·프로젝트·학습 기록·콘텐츠·개발 현황을 하나의 source of truth로 관리하는 개인 작업 공간이자 포트폴리오 백엔드다.

---

## 최상위 디렉터리별 역할 추정

| 디렉터리 | 역할 |
|---|---|
| `app/` | 실제 서비스 코드 (back/front/worker/scripts) |
| `persona/` | 프로필 데이터, 알고리즘 풀이, 커리어, 일일 기록, 콘텐츠 |
| `products/` | 개별 제품 문서 (kknaks-dev, mac-remote, open-kknaks 등 8개) |
| `context/` | 에이전트 라우팅 — 회사(company) vs 개인(studio) 분기 |
| `rules/` | product-doc-pipeline 등 문서 검증 규칙 |
| `templates/` | 제품 문서 템플릿 (spec, work 등) |
| `medi_docs/` | 회사(MediSolve) 관련 문서 |
| `claude_design/` | 디자인 에셋 (CLAUDE.md, SLOTS.md) |
| `.agent/` | 에이전트 설정·훅·스크립트 |

---

## 다음에 오케스트레이션으로 시켜보면 좋을 작업

**`products/` 상태 일괄 감사**: 각 product 디렉터리의 spec/work 문서가 템플릿 규칙을 따르는지 product-doc-pipeline 훅으로 검증하고, 미흡한 항목을 목록화하는 태스크. 현재 8개 product가 있어 병렬 에이전트 fan-out 효과가 크다.
