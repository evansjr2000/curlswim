# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

This project maintains a swim times report for two College Area Swim Team (CAST) swimmers. It generates a landscape PDF with each swimmer's best short course yard (SCY) times alongside motivational performance standards and age-group championship qualifying times.

## Swimmers

- **Kalea Benavente** — 13–14 Girls age group
- **Stella Julianna Evans** — 10 & Under Girls age group

## Workflow

1. Look up swimmer times at https://data.usaswimming.org/datahub/usas/individualsearch — always fetch live, never guess. Do **not** use Swimcloud (https://www.swimcloud.com/) — it has errors.
2. Update `swim/swim-times.md` with new times, dates, and meet names.
3. Generate output from the `swim/` directory:

```bash
# Generate PDF (landscape via pdflscape LaTeX package in the YAML header)
pandoc swim-times.md -o swim-times.pdf --pdf-engine=xelatex

# Generate HTML
pandoc swim-times.md -o swim-times.html
```

## Data Sources

- **Swimmer times**: USA Swimming data hub (URL above) — live lookup required
- **Motivational standards (B, BB, A)**: `swim/motivational-time-standards.pdf` — do not look up online
- **SDI Age Group Championships qualifying times**: `swim/sdi-agc-time-standards.pdf` — do not look up online

## Document Structure

`swim/swim-times.md` uses a pandoc Markdown YAML front matter block (landscape PDF, LaTeX packages) followed by two swimmer sections. Each section has a table with columns:

`Event | Best Time | Date | Meet | Mot. B | Mot. BB | Mot. A | SDI AGC Qual.`

`swim/swim-times.tex` is an equivalent direct LaTeX implementation using landscape geometry and CAST blue (RGB: 0,48,135).

## Planned Automation

`swim2/` is intended to hold bash scripts that use `curl` to programmatically fetch each swimmer's best SCY times from the USA Swimming data hub API (`https://data.usaswimming.org/datahub/usas/individualsearch/times`).
