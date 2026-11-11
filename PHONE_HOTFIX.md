# Phone launcher hotfix

The original V2.8.3 launcher could print a blank LAN address (`http://:8819`) on some Windows systems because its PowerShell adapter query returned no address. This hotfix replaces that detection with a language-independent route-based IPv4 lookup and adds a clear `ipconfig` fallback.

No Rosa application logic, database schema, permissions, or AI behavior changed.
