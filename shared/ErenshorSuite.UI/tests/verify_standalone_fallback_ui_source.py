from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "StandaloneFallbackUi.cs").read_text(encoding="utf-8")


def require(cond, msg):
    if not cond:
        raise AssertionError(msg)


# Regression guard for the "Can't add 'FallbackChevronGraphic' ... a 'Image' is already added"
# flood: FallbackChevronGraphic (Graphic-derived) must never be AddComponent'd onto the same
# GameObject/RectTransform that AddButton() already put an Image (also Graphic-derived) on. Unity
# does not throw for that conflict - it logs the error and returns null - so any line that adds the
# chevron directly to a button rect and then dereferences the result reintroduces a NullReference
# that unwinds through EnsureBuilt's catch and rebuilds (and re-fails) every single frame.
require(
    "collapse.gameObject.AddComponent<FallbackChevronGraphic>()" not in SOURCE,
    "FallbackChevronGraphic must not be added directly to the collapse button's own GameObject; "
    "give it a dedicated child (see EnsureChevron).",
)
require(
    "AddComponent<FallbackChevronGraphic>" in SOURCE,
    "FallbackChevronGraphic wiring appears to have been removed entirely.",
)

# The chevron must live on its own child RectTransform created via Child(...), not on "owner"
# itself, and must be looked up/reused rather than unconditionally recreated.
require(
    'Transform existing = owner.Find("Chevron")' in SOURCE,
    "EnsureChevron must look up an existing \"Chevron\" child before creating a new one "
    "(idempotent reuse).",
)
require(
    "RectTransform rect = Child(\"Chevron\", owner," in SOURCE,
    "EnsureChevron must create the chevron on its own dedicated child RectTransform, not on the "
    "button GameObject passed in as \"owner\".",
)
require(
    "graphic.raycastTarget = false" in SOURCE,
    "The chevron overlay must not steal the collapse button's raycast/click target.",
)

# BuildPanel must not run more than once per built root: EnsureBuilt's "_root != null" guard is
# what turns a single bad AddComponent into a bounded one-time failure instead of a per-frame flood.
require(
    "if (_root != null) return true;" in SOURCE,
    "EnsureBuilt must remain guarded so a successful build is never redundantly repeated.",
)

# SetCollapsed must reuse the existing chevron(s) rather than rebuilding the panel.
require(
    "GetComponentsInChildren<FallbackChevronGraphic>(true)" in SOURCE,
    "SetCollapsed must toggle existing chevron instances, not rebuild the panel.",
)

# Dispose must fully release the built hierarchy and every field that could otherwise retain a
# stale chevron/root reference across a Lunaris unload -> reload cycle.
require(
    "DestroyImmediate(_root)" in SOURCE,
    "Dispose must destroy the whole built hierarchy (including any chevron children).",
)
require(
    "_root = _launcherObject = _panelObject = null" in SOURCE,
    "Dispose must clear the root/launcher/panel references so a stale hierarchy is never reused.",
)

print("verify_standalone_fallback_ui_source: PASS")
