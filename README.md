# WebotApp Universal GitHub Project Installer & Local Development Manager

[![Download macOS DMG](https://img.shields.io/badge/Download-macOS%20DMG%20(v1.1.0)-000000?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/webotapp-academy/universal-github-installer/raw/release-downloads/WebotApp-Universal-GitHub-Installer-macOS.dmg)
[![Direct Download](https://img.shields.io/badge/Direct%20Download-macOS%20Installer-success?style=for-the-badge)](https://github.com/webotapp-academy/universal-github-installer/raw/release-downloads/WebotApp-Universal-GitHub-Installer-macOS.dmg)
[![Download Windows ZIP](https://img.shields.io/badge/Download-Windows%20x64%20(v1.1.0)-0078D6?style=for-the-badge&logo=windows&logoColor=white)](https://github.com/webotapp-academy/universal-github-installer/raw/release-downloads/WebotApp-Universal-GitHub-Installer-Windows-x64.zip)
[![Direct Download](https://img.shields.io/badge/Direct%20Download-Windows%20Portable%20ZIP-0078D6?style=for-the-badge)](https://github.com/webotapp-academy/universal-github-installer/raw/release-downloads/WebotApp-Universal-GitHub-Installer-Windows-x64.zip)

> 🍏 **[Click here to Download WebotApp-Universal-GitHub-Installer-macOS.dmg (20 MB)](https://github.com/webotapp-academy/universal-github-installer/raw/release-downloads/WebotApp-Universal-GitHub-Installer-macOS.dmg)**  
> *Ready-to-use release installer for macOS (Apple Silicon M1/M2/M3/M4 & Intel).*
>
> 🪟 **[Click here to Download WebotApp-Universal-GitHub-Installer-Windows-x64.zip (12 MB)](https://github.com/webotapp-academy/universal-github-installer/raw/release-downloads/WebotApp-Universal-GitHub-Installer-Windows-x64.zip)**  
> *Ready-to-use portable Windows x64 release (extract and run `github_installer.exe`).*

A production-ready, open-source desktop application for macOS and Windows built with Flutter that allows anyone to install, manage, execute, test, and expose multiple GitHub projects through one intuitive interface.

---

## 🚀 Key Features

- **GitHub Project Importer**: Paste any public or private GitHub repository URL. The system validates the repo, fetches metadata, clones it, and analyzes its dependencies.
- **Modular Technology Detection Engine**: Automatically detects:
  - **Node.js**: Next.js, Express, React, Vue, Angular, Nuxt, NestJS, Vite.
  - **PHP**: Laravel, CodeIgniter 3/4, WordPress, Symfony, Core PHP, Composer.
  - **Python**: Django, Flask, FastAPI, Streamlit, and standard Python scripts.
  - **Docker Compose & Static Websites**.
- **Automated Dependency & Runtime Management**:
  - Detects installed system runtimes (Node, npm, pnpm, yarn, Python, pip, poetry, uv, PHP, Composer, Docker, SQLite, MySQL, Postgres, Cloudflared).
  - Automatically isolates Python projects in `.venv` virtual environments.
  - Generates framework-specific execution plans with step-by-step progress.
- **Multiple Project Dashboard**:
  - Run unlimited projects simultaneously with automatic port conflict detection and dynamic port allocation.
  - Individual process monitoring, restart controls, real-time streaming terminal output, and direct browser launching.
- **Integrated Database Manager**:
  - Out-of-the-box SQLite zero-configuration database provisioning.
  - MySQL, MariaDB, PostgreSQL, and MongoDB connection testing and configuration.
  - Automatic `.env` generation and credentials synchronization.
- **Expose My Project (Tunnel Manager)**:
  - Securely expose local development servers to the internet using Cloudflare Tunnels (`cloudflared`).
  - Generate instant public HTTPS URLs for client demos or webhook testing with integrated security advisories.
- **Automated Testing Center**:
  - Detects Jest, Vitest, pytest, unittest, PHPUnit, and Pest.
  - Runs test suites with parsed pass/fail metrics, HTTP health endpoint verification, and database connectivity tests.
- **AI Development Assistant**:
  - Deep code understanding powered by Google Gemini, OpenAI ChatGPT, Anthropic Claude, OpenRouter, or local Ollama.
  - Instant actions: Explain Architecture, Troubleshoot Recent Errors, Suggest Tests, and Security Audit Checklist.
- **Security & Authorization**:
  - Static secret scanning for exposed API tokens and dangerous shell scripts before running.
  - Interactive command authorization dialog for database migrations and destructive operations.
  - Encrypted credential vault for API keys.

---

## 💻 Tech Stack & Architecture

- **UI Framework**: Flutter Desktop (Material Design 3 with Dark and Light themes)
- **State Management**: Provider (Separation of concerns, clean architecture)
- **Persistence**: File-backed JSON / SQLite project store
- **Process Management**: Native cross-platform `dart:io` streaming process execution
- **CI/CD**: GitHub Actions release automation for Windows (`.exe` installer & portable `.zip`) and macOS (`.dmg` & `.zip`).

---

## 🛠️ Getting Started

### Prerequisites

- [Flutter SDK (>= 3.24.0)](https://flutter.dev/docs/get-started/install)
- Git installed on your system

### Installation & Local Run

```bash
# Clone the repository
git clone https://github.com/webotapp-academy/universal-github-installer.git
cd universal-github-installer

# Get Flutter dependencies
flutter pub get

# Run tests
flutter test

# Run static analysis
flutter analyze

# Launch macOS Desktop App
flutter run -d macos

# Launch Windows Desktop App
flutter run -d windows
```

---

## 📦 Releases

Download pre-compiled binaries from the [GitHub Releases](https://github.com/webotapp-academy/universal-github-installer/releases) page:
- **macOS**: `github-installer-macos.dmg` or portable `.zip` (Apple Silicon & Intel)
- **Windows**: `github-installer-windows-x64-portable.zip`

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).
