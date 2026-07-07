import socket

import pytest

from app import __main__ as cli


def test_port_in_use_false_when_nothing_listening() -> None:
    # Port 1 is a privileged port nothing in this test suite binds to.
    assert cli._port_in_use("127.0.0.1", 1) is False


def test_port_in_use_true_when_something_listening() -> None:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as server:
        server.bind(("127.0.0.1", 0))
        server.listen(1)
        port = server.getsockname()[1]
        assert cli._port_in_use("127.0.0.1", port) is True


def test_port_in_use_probes_loopback_for_wildcard_host() -> None:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as server:
        server.bind(("127.0.0.1", 0))
        server.listen(1)
        port = server.getsockname()[1]
        assert cli._port_in_use("0.0.0.0", port) is True


def test_main_exits_when_port_already_in_use(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("OCR_SHARED_SECRET", "test-secret")
    monkeypatch.setattr(cli, "_load_root_dotenv", lambda: None)
    monkeypatch.setattr(cli, "_maybe_set_tesseract_cmd", lambda: None)
    monkeypatch.setattr(cli, "_port_in_use", lambda host, port: True)

    with pytest.raises(SystemExit) as exc_info:
        cli.main()

    assert exc_info.value.code == 1
