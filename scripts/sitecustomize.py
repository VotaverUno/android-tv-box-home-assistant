"""sitecustomize.py - Termux/Android DNS workaround (loaded automatically by venv Python).

Problem on this Android build:
  * pycares 5.2.1 supports raw `query()` (A/AAAA) but its `getaddrinfo()` fails
    instantly with ENOTIMP ("DNS server does not implement requested operation").
  * aiohttp's AsyncResolver (used by Home Assistant's shared HTTP client) calls
    aiodns.getaddrinfo + resp.nodes, so every outbound HTTPS request fails with
    "Could not contact DNS servers" -> all cloud logins (Midea/Haier/Xiaomi) fail.
  * simply hiding aiodns does not work: Home Assistant's HassAsyncDNSResolver
    requires it ("Resolver requires aiodns library").

Fix: keep the aiodns object (so HA's resolver classes can be constructed) but replace
aiohttp.resolver.AsyncResolver.resolve() with an implementation that uses the system
(C library) resolver via loop.getaddrinfo -- the same approach as ThreadedResolver,
which works correctly here. Home Assistant's resolver subclasses this class, so they
all benefit.
"""

import asyncio
import socket


def _patch_aiohttp_async_resolver() -> None:
    try:
        import aiohttp.resolver as resolver_mod
    except Exception:  # pragma: no cover - aiohttp always present in the HA venv
        return

    async_resolver = resolver_mod.AsyncResolver
    if getattr(async_resolver, "_termux_patched", False):
        return

    resolve_result = resolver_mod.ResolveResult
    ai_addrconfig = resolver_mod._AI_ADDRCONFIG
    numeric_flags = resolver_mod._NUMERIC_SOCKET_FLAGS

    async def resolve(self, host, port=0, family=socket.AF_INET):
        """Resolve using the system resolver (works on Android), aiodns replaces it."""
        loop = asyncio.get_running_loop()
        infos = await loop.getaddrinfo(
            host,
            port,
            type=socket.SOCK_STREAM,
            family=family,
            flags=ai_addrconfig,
        )
        results = []
        for fam, _type, proto, _canon, address in infos:
            resolved_host, resolved_port = address[:2]
            results.append(
                resolve_result(
                    hostname=host,
                    host=resolved_host,
                    port=resolved_port,
                    family=fam,
                    proto=proto,
                    flags=numeric_flags,
                )
            )
        return results

    async_resolver.resolve = resolve  # type: ignore[assignment]
    async_resolver._termux_patched = True  # type: ignore[attr-defined]


_patch_aiohttp_async_resolver()
