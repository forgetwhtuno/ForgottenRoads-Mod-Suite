# ErenshorSuite.UI (planned, Phase 2+)

Not yet implemented. This will hold the small shared UI contract every dedicated mod page
implements to appear in the Suite Hub, conceptually:

```csharp
interface ISuiteModPage
{
    string Id { get; }
    string DisplayName { get; }
    string Version { get; }
    string StatusSummary { get; }
    void DrawPage();
    bool HasDedicatedPanel { get; }
    void OpenDedicatedPanel();
    // Optional
    void DrawAdvancedPage();
}
```

Deliberately small — not a framework. The Suite Hub is never authoritative for gameplay state; it
only invokes safe public controls each mod already exposes and displays what each mod reports.
Mods remain fully functional (commands, dedicated panels, everything) with the Hub absent.

See `Erenshor-Mod-Suite/docs/ARCHITECTURE.md` and `docs/UI_DESIGN.md` for the surrounding design,
and `AGENTS.md` for why no Lunaris Aura APIs should be invented here — verify Aura's actual current
capabilities before assuming it's the right registration mechanism; a narrow, documented,
absent-safe reflection/interface bridge is the fallback if Aura isn't yet suitable.
