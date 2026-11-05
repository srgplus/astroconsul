"""The database pool's size from the environment (SRG-1125): a Sites preview shares 15 pooler clients with the live server."""

from __future__ import annotations

import os
import unittest
from unittest import mock

from app.infrastructure.persistence.session import pool_options


class PoolOptionsTests(unittest.TestCase):
    def test_defaults_when_unset(self) -> None:
        env = {k: v for k, v in os.environ.items() if not k.startswith("ASTRO_CONSUL_DB_")}
        with mock.patch.dict(os.environ, env, clear=True):
            self.assertEqual(pool_options(), {})

    def test_small_pool_from_env(self) -> None:
        with mock.patch.dict(os.environ, {"ASTRO_CONSUL_DB_POOL_SIZE": "1", "ASTRO_CONSUL_DB_MAX_OVERFLOW": "0"}):
            self.assertEqual(pool_options(), {"pool_size": 1, "max_overflow": 0})

    def test_unreadable_values_keep_the_defaults(self) -> None:
        with mock.patch.dict(os.environ, {"ASTRO_CONSUL_DB_POOL_SIZE": "0", "ASTRO_CONSUL_DB_MAX_OVERFLOW": "lots"}):
            self.assertEqual(pool_options(), {})


if __name__ == "__main__":
    unittest.main()
