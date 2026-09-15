"""Shared test helpers."""
import time


def wait_until(predicate, timeout: float = 5.0, interval: float = 0.01) -> bool:
    """Poll until predicate() is true. Delivery is now drained by a background
    worker, so a request returning is no longer proof that the push has gone."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return True
        time.sleep(interval)
    return predicate()
