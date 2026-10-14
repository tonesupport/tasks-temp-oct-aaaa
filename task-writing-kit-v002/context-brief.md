# Context brief
- tasks.toml is the user's single task list. A pipeline renders it into the Sight board, with cards as id pills and tag meta.
- almanac.tcl is the sanctioned reader and writer; it also applies patches (`apply`) and renders previews (`preview`). Inside this kit it runs on your copy. ALMANAC_SKIP_BOARD_EXPORT=1 keeps it from triggering the live board export.
- The snapshot was taken 2026-10-13: 341 tasks, sha256 in snapshot/SHA256. If the live file has moved on, `almanac apply` rebases per task id and reports conflicts. That isn't your job.
- The survey (inputs/260710-001-ground-truth-survey.md) is a July 2026 personal planning survey with inline `{{annotations}}`. Many items have since been done or are already tracked, for example the Dropbox→MEGA migration, ITAA, therapy, OCR, and guidebooks. Check the snapshot before adding anything.
- Data files are TOML, never JSON. All repos are private.
