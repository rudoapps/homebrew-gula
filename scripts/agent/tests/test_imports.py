"""Import tests — verify all modules can be imported without errors.

Run: python3 scripts/agent/tests/test_imports.py
"""

import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

MODULES = [
    # Domain
    "gula_chat.domain.entities.tool_call",
    "gula_chat.domain.entities.tool_result",
    "gula_chat.domain.entities.skill",
    "gula_chat.domain.entities.sse_event",
    "gula_chat.domain.entities.config",
    "gula_chat.domain.entities.permission_mode",

    # Application
    "gula_chat.application.ports.driven.api_client_port",
    "gula_chat.application.ports.driven.tool_executor_port",
    "gula_chat.application.ports.driven.config_port",
    "gula_chat.application.services.auth_service",
    "gula_chat.application.services.chat_service",
    "gula_chat.application.services.skill_service",
    "gula_chat.application.services.tool_orchestrator",

    # Driven - Tools
    "gula_chat.driven.tools.base",
    "gula_chat.driven.tools.file_tools",
    "gula_chat.driven.tools.search_tools",
    "gula_chat.driven.tools.shell_tools",
    "gula_chat.driven.tools.code_analysis_tools",
    "gula_chat.driven.tools.web_tools",
    "gula_chat.driven.tools.local_executor",
    "gula_chat.driven.tools.path_validator",
    "gula_chat.driven.tools.file_backup",

    # Driven - Other
    "gula_chat.driven.hooks.hook_runner",
    "gula_chat.driven.memory.local_memory",
    "gula_chat.driven.notifications.os_notify",
    "gula_chat.driven.context.project_context_builder",
    "gula_chat.driven.api.httpx_client",
    "gula_chat.driven.api.payload_builder",

    # Driving - CLI
    "gula_chat.driving.cli.commands",
    "gula_chat.driving.cli.input_handler",
    "gula_chat.driving.cli.handlers.startup",
    "gula_chat.driving.cli.handlers.git_handler",
    "gula_chat.driving.cli.handlers.model_handler",
    "gula_chat.driving.cli.handlers.context_handler",

    # Driving - UI
    "gula_chat.driving.ui.console",
    "gula_chat.driving.ui.header",
    "gula_chat.driving.ui.renderer",
    "gula_chat.driving.ui.selector",
    "gula_chat.driving.ui.spinner",
    "gula_chat.driving.ui.markdown",
    "gula_chat.driving.ui.tool_display",
]


def test_imports():
    """Test that all modules can be imported."""
    passed = 0
    failed = 0
    errors = []

    for module_path in MODULES:
        try:
            __import__(module_path)
            print(f"  \033[32m✓\033[0m {module_path}")
            passed += 1
        except Exception as e:
            print(f"  \033[31m✗\033[0m {module_path} — {e}")
            failed += 1
            errors.append(f"{module_path}: {e}")

    print()
    print(f"  Results: {passed} passed, {failed} failed, {len(MODULES)} total")

    if errors:
        print()
        print("  Failures:")
        for e in errors:
            print(f"    - {e}")

    return failed == 0


if __name__ == "__main__":
    print()
    print("  Running import tests...")
    print()
    ok = test_imports()
    sys.exit(0 if ok else 1)
