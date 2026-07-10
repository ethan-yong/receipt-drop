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


def test_ensure_port_available_frees_busy_port(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    calls: list[int] = []
    state = {"busy": True}

    def fake_port_in_use(host: str, port: int) -> bool:
        return state["busy"]

    def fake_free_port(port: int) -> None:
        calls.append(port)
        state["busy"] = False

    monkeypatch.setattr(cli, "_port_in_use", fake_port_in_use)
    monkeypatch.setattr(cli, "_free_port", fake_free_port)

    cli._ensure_port_available("0.0.0.0", 8081)
    assert calls == [8081]


def test_ensure_port_available_exits_when_still_busy(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(cli, "_port_in_use", lambda host, port: True)
    monkeypatch.setattr(cli, "_free_port", lambda port: None)

    with pytest.raises(SystemExit) as exc_info:
        cli._ensure_port_available("0.0.0.0", 8081)

    assert exc_info.value.code == 1
