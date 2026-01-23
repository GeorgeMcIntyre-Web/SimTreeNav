# Contributing to SimTreeNav

Thank you for your interest in contributing to SimTreeNav! This document represents our guidelines for contributing to this project.

## Code of Conduct

Please maintain a respectful and professional environment in all interactions.

## Getting Started

1. Clone the repository
2. Ensure you have the required prerequisites (PowerShell 7+, Node.js if applicable)
3. Explore the `docs/` directory for system architecture and guides
4. Check `scripts/` for operational tools

## Development Workflow

1. Create a feature branch from `main`
2. Implement your changes
3. Run local tests before submitting
4. Submit a Pull Request

## Style Guidelines

- **PowerShell**: Follow PSScriptAnalyzer rules. Use 4 spaces for indentation.
- **Markdown**: Use standard GFM syntax.
- **Commit Messages**: Use clear, descriptive summaries (e.g., "Fix: Handle null values in tree parser").

## Directory Structure

- `src/`: Source code
- `scripts/`: Operational and helper scripts
  - `scripts/lib/`: Shared libraries
  - `scripts/ops/`: Operational tasks
  - `scripts/debug/`: Debugging and analysis tools
- `test/`: Test infrastructure
- `docs/`: Documentation

## Reporting Issues

Please file issues using the provided templates, including reproduction steps and logs where applicable.
