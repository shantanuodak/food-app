# FR Traceability Matrix - MVP Delta (2026-02-28)

Source requirements file: `/Users/shantanuodak/Desktop/Notes for GPT/FUNCTIONAL_REQUIREMENTS_UPDATED.md`

This matrix lists every `FR-*` entry from the updated requirements file and maps it to source docs, ownership, Jira tickets, sprint target, and delivery risk.

Legend:
- `Sprint Legacy` = already covered in existing sprint cut
- `Sprint A/B/C/D` = delta alignment sprints added in backlog update
- `N/A (Implemented)` = no new delivery sprint required

| FR ID | Current Status | Source Doc Section | Implementation Owner | Jira Mapping | Target Sprint | Risk |
|---|---|---|---|---|---|---|
| FR-SCOPE-001 | Implemented | PRD Sec 2-6 | iOS + Product | FE-006 | N/A (Implemented) | Low |
| FR-SCOPE-002 | Implemented | PRD Sec 4-5 | iOS | FE-003, FE-006 | N/A (Implemented) | Low |
| FR-SCOPE-003 | Implemented | PRD Sec 4 | iOS | FE-003 | N/A (Implemented) | Low |
| FR-SCOPE-004 | Implemented | PRD Sec 4 | iOS + Product | FE-003, FE-010 | N/A (Implemented) | Low |
| FR-AUTH-001 | Partial | PRD Sec 4 + Sec 11D | BE + iOS | BE-003, FE-003 | Sprint Legacy | Medium |
| FR-AUTH-002 | Implemented | PRD Sec 4 | iOS + BE | FE-005, BE-003 | N/A (Implemented) | Low |
| FR-AUTH-003 | Partial | PRD Sec 4 | iOS + BE | FE-005, BE-003 | Sprint Legacy | Medium |
| FR-AUTH-004 | Implemented | PRD Sec 4 | iOS | FE-002, FE-003 | N/A (Implemented) | Low |
| FR-AUTH-005 | Implemented | PRD Sec 8 | BE | BE-003 | N/A (Implemented) | Low |
| FR-AUTH-006 | Pending | PRD Sec 4 (deferred policy) | Product + BE + iOS | Deferred (post-MVP) | Backlog Parking Lot | Medium |
| FR-ONB-001 | Implemented | PRD Sec 4-5 | iOS | FE-005 | N/A (Implemented) | Low |
| FR-ONB-002 | Implemented | PRD Sec 5 | iOS + BE | FE-005, BE-005 | N/A (Implemented) | Low |
| FR-ONB-003 | Implemented (client-side) | PRD Sec 5 | iOS | FE-005 | N/A (Implemented) | Low |
| FR-ONB-004 | Implemented (client-side) | PRD Sec 5 | iOS | FE-005 | N/A (Implemented) | Low |
| FR-ONB-005 | Implemented | PRD Sec 5 | iOS + BE | FE-005, BE-005 | N/A (Implemented) | Low |
| FR-ONB-006 | Implemented | PRD Sec 5 + Sec 11C | iOS | FE-005, FE-010 | N/A (Implemented) | Low |
| FR-ONB-007 | Implemented | PRD Sec 4-5 | iOS + BE | FE-005, BE-005 | N/A (Implemented) | Low |
| FR-ONB-008 | Implemented | PRD Sec 5 | iOS | FE-005 | N/A (Implemented) | Low |
| FR-ONB-009 | Implemented | PRD Sec 9 | BE | BE-005 | N/A (Implemented) | Low |
| FR-ONB-008 (integrity) | Pending | PRD Sec 11D + Spec Sec 7.3 | BE | BE-025 | Sprint A | High |
| FR-HOME-001 | Implemented | PRD Sec 5 | iOS | FE-006 | N/A (Implemented) | Low |
| FR-HOME-002 | Implemented | PRD Sec 5 | iOS | FE-006 | N/A (Implemented) | Low |
| FR-HOME-003 | Implemented | PRD Sec 5 | iOS | FE-006 | N/A (Implemented) | Low |
| FR-HOME-004 | Pending | PRD Sec 11A | iOS + BE | FE-012, BE-029 | Sprint A | High |
| FR-HOME-005 | Implemented | PRD Sec 5 | iOS | FE-006 | N/A (Implemented) | Low |
| FR-LOG-001 | Implemented | PRD Sec 5-6 | iOS | FE-006 | N/A (Implemented) | Low |
| FR-LOG-002 | Implemented | PRD Sec 5 | iOS | FE-006 | N/A (Implemented) | Low |
| FR-LOG-003 | Implemented | PRD Sec 5 | iOS | FE-006 | N/A (Implemented) | Low |
| FR-LOG-004 | Partial | Spec Sec 6.4 | iOS | FE-011 | Sprint B | Medium |
| FR-LOG-005 | Implemented | PRD Sec 6 | iOS | FE-006 | N/A (Implemented) | Low |
| FR-LOG-006 | Implemented | PRD Sec 5 | iOS | FE-006 | N/A (Implemented) | Low |
| FR-LOG-007 | Pending | PRD Sec 19 | iOS | FE-016 | Sprint C | Medium |
| FR-LOG-008 | Partial | PRD Sec 19 | iOS | FE-017 | Sprint C | Medium |
| FR-PARSE-001 | Implemented | PRD Sec 7 | BE | BE-012, BE-013 | N/A (Implemented) | Low |
| FR-PARSE-002 | Implemented | PRD Sec 7 | BE | BE-013 | N/A (Implemented) | Low |
| FR-PARSE-003 | Implemented | PRD Sec 7 | BE | BE-012 | N/A (Implemented) | Low |
| FR-PARSE-004 | Implemented | PRD Sec 7 | BE | BE-013 | N/A (Implemented) | Low |
| FR-PARSE-005 | Implemented | PRD Sec 7 | BE | BE-013 | N/A (Implemented) | Low |
| FR-PARSE-006 | Implemented | PRD Sec 6-7 | BE | BE-006, BE-008, BE-009 | N/A (Implemented) | Low |
| FR-PARSE-007 | Implemented | PRD Sec 6-7 | BE | BE-006 | N/A (Implemented) | Low |
| FR-PARSE-008 | Implemented | PRD Sec 10 | BE | BE-009, BE-014 | N/A (Implemented) | Low |
| FR-PARSE-009 | Implemented | PRD Sec 7 + 10 | BE | BE-013 | N/A (Implemented) | Low |
| FR-PARSE-009A | Pending | PRD Sec 7 + Sec 10 | BE | BE-026 | Sprint A | High |
| FR-PARSE-010 | Implemented | PRD Sec 10 | BE | BE-009, BE-010 | N/A (Implemented) | Low |
| FR-PARSE-011 | Pending | PRD Sec 10 + Spec Sec 5.1 | BE | BE-026 | Sprint A | High |
| FR-PARSE-012 | Partial | Spec Sec 5.4 + 6.4 | BE | BE-027 | Sprint A | High |
| FR-DETAIL-001 | Implemented | PRD Sec 5 | iOS | FE-007 | N/A (Implemented) | Low |
| FR-DETAIL-002 | Implemented | PRD Sec 5 + 10 | iOS | FE-007 | N/A (Implemented) | Low |
| FR-DETAIL-003 | Implemented | PRD Sec 5 + 10 | iOS | FE-007, FE-008 | N/A (Implemented) | Low |
| FR-DETAIL-004 | Implemented | PRD Sec 6 + 11B | iOS | FE-007 | N/A (Implemented) | Low |
| FR-DETAIL-005 | Implemented | PRD Sec 5 | iOS | FE-007 | N/A (Implemented) | Low |
| FR-DETAIL-006 | Implemented | PRD Sec 5 | iOS | FE-007 | N/A (Implemented) | Low |
| FR-SAVE-001 | Implemented | PRD Sec 10 | BE + iOS | BE-010, FE-009 | N/A (Implemented) | Low |
| FR-SAVE-002 | Implemented | PRD Sec 10 | BE + iOS | BE-010, FE-009 | N/A (Implemented) | Low |
| FR-SAVE-003 | Implemented | PRD Sec 10 | BE | BE-010 | N/A (Implemented) | Low |
| FR-SAVE-004 | Implemented | PRD Sec 10 | iOS + BE | FE-009, BE-010 | N/A (Implemented) | Low |
| FR-SAVE-005 | Implemented | PRD Sec 7 + 10 | BE + iOS | BE-014, FE-008, FE-009 | N/A (Implemented) | Low |
| FR-SAVE-006 | Implemented | PRD Sec 6 | iOS | FE-009 | N/A (Implemented) | Low |
| FR-SAVE-007 | Implemented | PRD Sec 6 | iOS | FE-009 | N/A (Implemented) | Low |
| FR-SAVE-008 | Pending | PRD Sec 11B + Spec Sec 5.4 | BE + iOS | BE-028, FE-013 | Sprint B | High |
| FR-SAVE-009 | Pending | PRD Sec 10 + 11B | BE | BE-028 | Sprint B | High |
| FR-SUM-001 | Implemented | PRD Sec 10 | iOS + BE | BE-011, FE-010 | N/A (Implemented) | Low |
| FR-SUM-002 | Implemented | PRD Sec 10 | iOS + BE | BE-011, FE-010 | N/A (Implemented) | Low |
| FR-SUM-003 | Implemented | PRD Sec 10 | iOS + BE | BE-011, FE-010 | N/A (Implemented) | Low |
| FR-SUM-004 | Implemented | PRD Sec 10 | BE + iOS | BE-011, FE-010 | N/A (Implemented) | Low |
| FR-SUM-005 | Pending | PRD Sec 11A + Spec Sec 6.4 | BE + iOS | BE-029, FE-012 | Sprint A | High |
| FR-PRO-001 | Implemented | PRD Sec 5 | iOS | FE-005, FE-010 | N/A (Implemented) | Low |
| FR-PRO-002 | Implemented | PRD Sec 5 | iOS | FE-010 | N/A (Implemented) | Low |
| FR-PRO-003 | Implemented | PRD Sec 5 | iOS | FE-010 | N/A (Implemented) | Low |
| FR-PRO-004 | Implemented | PRD Sec 11C | iOS | FE-015 | Sprint C | Medium |
| FR-PRO-005 | Implemented | PRD Sec 5 | iOS | FE-005, FE-010 | N/A (Implemented) | Low |
| FR-ESC-001 | Implemented | PRD Sec 7 + 10 | iOS + BE | BE-014, FE-008 | N/A (Implemented) | Low |
| FR-ESC-002 | Implemented | PRD Sec 7 | iOS + BE | BE-015, FE-008 | N/A (Implemented) | Low |
| FR-ESC-003 | Implemented | PRD Sec 10 | BE | BE-015 | N/A (Implemented) | Low |
| FR-ESC-004 | Implemented | PRD Sec 11 | iOS + BE | BE-017, FE-008 | N/A (Implemented) | Low |
| FR-HK-001 | Implemented | PRD Sec 11C | iOS | FE-010 | N/A (Implemented) | Low |
| FR-HK-002 | Implemented | PRD Sec 11C | iOS + BE | FE-010, BE-010 | N/A (Implemented) | Medium |
| FR-HK-003 | Implemented | PRD Sec 11C | iOS | FE-010 | N/A (Implemented) | Low |
| FR-HK-004 | Pending | PRD Sec 11C + Spec Sec 11A | BE + iOS | BE-030, FE-015 | Sprint C | High |
| FR-HK-005 | Pending | PRD Sec 11C + Spec Sec 11A | BE + iOS | BE-030, FE-015 | Sprint C | High |
| FR-ADMIN-001 | Implemented | PRD Sec 8 + 10 | BE + iOS | BE-003, FE-010 | N/A (Implemented) | Low |
| FR-ADMIN-002 | Implemented | PRD Sec 8 + 10 | BE + iOS | BE-003, FE-010 | N/A (Implemented) | Low |
| FR-ADMIN-003 | Implemented | PRD Sec 8 + 10 | BE | BE-003 | N/A (Implemented) | Low |
| FR-API-001 | Implemented | PRD Sec 10 | BE | BE-005, BE-009, BE-010, BE-011, BE-015 | N/A (Implemented) | Low |
| FR-API-002 | Implemented | PRD Sec 10 + Spec Sec 5 | BE + iOS | BE-009, BE-013, FE-002 | N/A (Implemented) | Low |
| FR-API-003 | Implemented | Spec Sec 5.4 | BE + iOS | BE-010, FE-009 | N/A (Implemented) | Low |
| FR-API-004 | Implemented | PRD Sec 10 | BE + iOS | BE-011, FE-010 | N/A (Implemented) | Low |
| FR-API-005 | Implemented | Spec Sec 10 | BE | BE-018, BE-019 | N/A (Implemented) | Low |
| FR-DATA-001 | Implemented | PRD Sec 9 | BE | BE-001, BE-002 | N/A (Implemented) | Low |
| FR-DATA-002 | Implemented | PRD Sec 9 | BE | BE-001 | N/A (Implemented) | Low |
| FR-DATA-003 | Pending | PRD Sec 9 + Spec Sec 8 | BE | BE-031 | Sprint B | High |
| FR-DATA-004 | Pending | PRD Sec 9 + Spec Sec 8 | BE | BE-031 | Sprint B | High |
| FR-DATA-004 (purge) | Implemented | Spec Sec 8 | BE/Ops | BE-031 (hardening) | Sprint B | Medium |
| FR-DATA-005 | Implemented | PRD Sec 6 + 10 | BE + iOS | BE-009, FE-007 | N/A (Implemented) | Low |
| FR-DATA-006 | Pending | PRD Sec 9 + Spec Sec 7.2 | BE | BE-028 | Sprint B | Medium |
| FR-REL-001 | Implemented | Spec Sec 6.4 | iOS + BE | FE-002, FE-006, FE-009 | N/A (Implemented) | Low |
| FR-REL-002 | Implemented | Spec Sec 5.3 | iOS + BE | FE-002, BE-004 | N/A (Implemented) | Low |
| FR-REL-003 | Implemented | PRD Sec 6 | iOS | FE-009 | N/A (Implemented) | Low |
| FR-REL-004 | Implemented | Spec Sec 4.1 | BE | BE-003, BE-017 | N/A (Implemented) | Low |
| FR-OBS-001 | Implemented | Spec Sec 10 | iOS | FE-004 | N/A (Implemented) | Low |
| FR-OBS-002 | Implemented | Spec Sec 10 | BE | BE-016 | N/A (Implemented) | Low |
| FR-OBS-003 | Implemented | Spec Sec 10 | BE | BE-018 | N/A (Implemented) | Low |
| FR-OBS-004 | Implemented | Spec Sec 9 + 10 | BE | BE-017, BE-018 | N/A (Implemented) | Low |
| FR-SEC-001 | Implemented | PRD Sec 13 + Spec Sec 11 | BE/Ops | BE-003, BE-024 | N/A (Implemented) | Low |
| FR-SEC-002 | Implemented | Spec Sec 11 | BE | BE-003, BE-001 | N/A (Implemented) | Low |
| FR-SEC-003 | Implemented | Spec Sec 11 | BE | BE-004, BE-016 | N/A (Implemented) | Low |

## Delta Execution Focus (Pending/Partial)

Primary delivery sequence for unresolved requirements:
- Sprint A: `BE-025`, `BE-026`, `BE-027`, `BE-029`, `FE-012`
- Sprint B: `BE-028`, `BE-031`, `FE-011`, `FE-013`, `FE-014`
- Sprint C: `BE-030`, `FE-015`, `FE-016`, `FE-017`
- Sprint D: E2E hardening extensions (`E2E-001`, `E2E-002`, `BE-022` regression expansion)
