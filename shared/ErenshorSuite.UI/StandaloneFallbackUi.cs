using System;
using System.Collections.Generic;
using Lunaris;
using Lunaris.IPC;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.UI;

namespace ForgottenRoads.StandaloneUi
{
    internal sealed class FallbackAction
    {
        internal string Label;
        internal Func<bool> Invoke;
        internal Func<bool> Enabled;

        internal FallbackAction(string label, Func<bool> invoke, Func<bool> enabled)
        { Label = label; Invoke = invoke; Enabled = enabled; }
    }

    // Source-linked into each owning module DLL. There is no shared runtime assembly and no Hub
    // dependency: an absent/malformed/unusable Hub presence descriptor fails open to the launcher.
    internal static class StandaloneFallbackUi
    {
        private const string HubEndpoint = "forgetwhtuno.erenshor.suitehub.v1.describe";
        private static readonly Color Panel = new Color32(4, 23, 32, 232);
        private static readonly Color Header = new Color32(6, 33, 43, 245);
        private static readonly Color ButtonFill = new Color32(9, 43, 56, 245);
        private static readonly Color Hover = new Color32(31, 97, 122, 250);
        private static readonly Color Pressed = new Color32(8, 171, 219, 255);
        private static readonly Color Cyan = new Color32(143, 224, 255, 255);

        // Canonical Forgotten Roads launcher chrome (matches StandaloneLauncherVisual, the
        // per-module copied reference implementation used by Journal and other suite mods).
        // Kept as its own constant block, self-contained, because this file is compiled into
        // more than one module namespace and must not depend on any per-module policy type.
        private const float LauncherWidth = 154f;
        private const float LauncherHeight = 32f;
        private const float LauncherGripWidth = 20f;
        private const float LauncherBorder = 1f;
        private static readonly Color LauncherBackground = new Color(0.015f, 0.09f, 0.125f, 0.72f);
        private static readonly Color LauncherGripBackground = new Color(0.025f, 0.13f, 0.17f, 0.88f);
        private static readonly Color LauncherCyan = new Color(0.03f, 0.67f, 0.86f, 0.95f);

        // Self-contained normalized-position math (mirrors SuiteUiPositionPolicy exactly) for
        // the same reason: no cross-module policy type can be referenced from shared source.
        private const float PositionUnset = -1f;

        private static string _moduleId, _title, _guide;
        private static float _defaultLauncherX, _defaultLauncherY;
        private static float _storedLauncherX = PositionUnset, _storedLauncherY = PositionUnset;
        private static int _launcherLastWidth = -1, _launcherLastHeight = -1;
        private static Func<string> _status;
        private static readonly List<FallbackAction> Actions = new List<FallbackAction>();
        private static IAuraSubscriber<string> _hub;
        private static float _nextHubProbe;
        private static bool _hubUsable;
        private static GameObject _root, _launcherObject, _panelObject;
        private static RectTransform _launcher, _panel;
        private static Image _panelBackground;
        private static Text _statusText;
        private static readonly List<Button> Buttons = new List<Button>();
        private static bool _open;
        private static bool _collapsed;
        private static Button _collapseButton;
        private static GameObject _openAccent;

        // Default status-box height and default-panel-workspace anchors are opt-in via
        // ConfigureWorkspaceDefaults, called after Initialize. A module that never calls it keeps
        // byte-for-byte the original behavior: an 88px status box and a dead-center panel default.
        private const float DefaultStatusHeight = 88f;
        private static float _statusHeight = DefaultStatusHeight;
        private static float _panelDefaultRightNormalized = PositionUnset;
        private static float _panelDefaultTopNormalized = PositionUnset;
        private static int _workspaceSlotIndex;
        // Small deterministic per-slot stagger so Journal/Duel/Follow panels sharing one default
        // workspace anchor do not open exactly on top of each other on a first-ever open.
        private const float PanelSlotStaggerPixels = 22f;

        internal static bool IsOpen { get { return _open; } }

        internal static void Initialize(LunarisPlugin owner, string moduleId, string title,
            string guide, float defaultLauncherX, float defaultLauncherY, Func<string> status, params FallbackAction[] actions)
        {
            Dispose();
            _moduleId = moduleId ?? string.Empty; _title = title ?? "MOD"; _guide = guide ?? string.Empty;
            _defaultLauncherX = defaultLauncherX; _defaultLauncherY = defaultLauncherY; _status = status;
            LoadLauncherPosition();
            if (actions != null) Actions.AddRange(actions);
            try { if (owner != null) _hub = owner.IPCAuraSubscriber<string>(HubEndpoint); } catch { _hub = null; }
        }

        // Opt-in workspace tuning called after Initialize, before the panel is first built. Kept as
        // a separate call rather than new Initialize parameters: Initialize's trailing params array
        // means any new fixed parameter inserted ahead of it would force positional binding onto
        // every existing FallbackAction argument at every current call site.
        internal static void ConfigureWorkspaceDefaults(float statusHeight, float panelDefaultRightNormalized, float panelDefaultTopNormalized, int slotIndex)
        {
            _statusHeight = statusHeight > 0f ? statusHeight : DefaultStatusHeight;
            _panelDefaultRightNormalized = Clamp01OrUnset(panelDefaultRightNormalized);
            _panelDefaultTopNormalized = Clamp01OrUnset(panelDefaultTopNormalized);
            _workspaceSlotIndex = slotIndex < 0 ? 0 : slotIndex;
        }

        private static float Clamp01OrUnset(float value)
        {
            if (!IsFinite(value) || value < 0f) return PositionUnset;
            return value > 1f ? 1f : value;
        }

        internal static void Tick(bool gameplayReady)
        {
            ProbeHub();
            if (!gameplayReady || EventSystem.current == null)
            {
                if (_root != null) _root.SetActive(false);
                return;
            }
            if (!EnsureBuilt()) return;
            _root.SetActive(true);
            ResolveLauncherPosition();
            _launcherObject.SetActive(!_hubUsable);
            _panelObject.SetActive(_open);
            // Structural (not color-only) open/active cue shared by every Forgotten Roads
            // standalone launcher: a filled top-edge accent bar, present only while open.
            if (_openAccent != null) _openAccent.SetActive(_open);
            if (_statusText != null)
            {
                string status = string.Empty;
                try { status = _status == null ? string.Empty : (_status() ?? string.Empty); } catch { status = "Status unavailable"; }
                _statusText.text = status + (string.IsNullOrEmpty(_guide) ? string.Empty : "\n\n" + _guide);
            }
            for (int i = 0; i < Buttons.Count && i < Actions.Count; i++)
            {
                bool enabled = true;
                try { enabled = Actions[i].Enabled == null || Actions[i].Enabled(); } catch { enabled = false; }
                Buttons[i].interactable = enabled;
            }
        }

        internal static bool Open() { _open = true; return true; }
        internal static bool Toggle() { _open = !_open; return true; }
        internal static bool Close() { _open = false; return true; }

        internal static void Dispose()
        {
            if (_root != null) try { UnityEngine.Object.DestroyImmediate(_root); } catch { }
            _root = _launcherObject = _panelObject = null; _launcher = _panel = null; _panelBackground = null; _statusText = null;
            Buttons.Clear(); Actions.Clear(); _hub = null; _hubUsable = false; _nextHubProbe = 0f; _open = false; _collapsed = false; _collapseButton = null;
            _launcherLastWidth = -1; _launcherLastHeight = -1; _openAccent = null;
            _statusHeight = DefaultStatusHeight; _panelDefaultRightNormalized = PositionUnset; _panelDefaultTopNormalized = PositionUnset; _workspaceSlotIndex = 0;
        }

        private static void ProbeHub()
        {
            if (Time.unscaledTime < _nextHubProbe) return;
            _nextHubProbe = Time.unscaledTime + 1f; _hubUsable = false;
            try
            {
                if (_hub == null || !_hub.HasFunction) return;
                string value = _hub.InvokeFunc() ?? string.Empty;
                _hubUsable = HasField(value, "status", "Ready") && HasField(value, "uiAvailable", "true");
            }
            catch { _hubUsable = false; }
        }

        private static bool HasField(string payload, string key, string value)
        {
            string[] fields = (payload ?? string.Empty).Split('&');
            for (int i = 0; i < fields.Length; i++)
            {
                int equals = fields[i].IndexOf('=');
                if (equals <= 0) continue;
                if (string.Equals(fields[i].Substring(0, equals), key, StringComparison.OrdinalIgnoreCase) &&
                    string.Equals(Uri.UnescapeDataString(fields[i].Substring(equals + 1)), value, StringComparison.OrdinalIgnoreCase)) return true;
            }
            return false;
        }

        private static bool EnsureBuilt()
        {
            if (_root != null) return true;
            try
            {
                _root = new GameObject("ForgottenRoads." + _moduleId + ".FallbackUI"); UnityEngine.Object.DontDestroyOnLoad(_root);
                Canvas canvas = _root.AddComponent<Canvas>(); canvas.renderMode = RenderMode.ScreenSpaceOverlay; canvas.overrideSorting = true; canvas.sortingOrder = 535;
                CanvasScaler scaler = _root.AddComponent<CanvasScaler>(); scaler.uiScaleMode = CanvasScaler.ScaleMode.ConstantPixelSize;
                _root.AddComponent<GraphicRaycaster>();
                BuildLauncher(); BuildPanel(); return true;
            }
            catch { Dispose(); return false; }
        }

        private static void BuildLauncher()
        {
            _launcherObject = MakePanel("Launcher", _root.transform, LauncherBackground);
            _launcher = Rect(_launcherObject, LauncherWidth, LauncherHeight);
            _launcher.anchorMin = _launcher.anchorMax = _launcher.pivot = Vector2.zero;
            AddLauncherFrame(_launcher);

            RectTransform grip = Child("Grip", _launcher, LauncherGripWidth, LauncherHeight, 0f, 0f);
            Image gi = grip.gameObject.AddComponent<Image>(); gi.color = LauncherGripBackground;
            FallbackDragGuard gd = grip.gameObject.AddComponent<FallbackDragGuard>(); gd.Target = _launcher;
            RectTransform accent = Child("GripAccent", grip, 2f, LauncherHeight, 0f, 0f);
            Image ai = accent.gameObject.AddComponent<Image>(); ai.color = LauncherCyan; ai.raycastTarget = false;
            for (int i = -1; i <= 1; i++)
            {
                RectTransform dot = Child("GripDot", grip, 2f, 2f, LauncherGripWidth * 0.5f - 1f, LauncherHeight * 0.5f - 1f + i * 5f);
                Image di = dot.gameObject.AddComponent<Image>(); di.color = LauncherCyan; di.raycastTarget = false;
            }

            RectTransform button = Child("Open", _launcher, LauncherWidth - LauncherGripWidth, LauncherHeight, LauncherGripWidth, 0f);
            AddButton(button, _title, delegate { Toggle(); });

            // Open/active-state indicator: a filled bar along the launcher's top edge, hidden
            // until the panel is open (toggled in Tick, never rebuilt). A structural element
            // rather than only a color swap, so open/closed reads even without color perception.
            RectTransform openAccent = Child("OpenAccent", _launcher, LauncherWidth - LauncherGripWidth - 2f, 3f, LauncherGripWidth + 1f, LauncherHeight - 3f);
            Image openAccentImage = openAccent.gameObject.AddComponent<Image>(); openAccentImage.color = LauncherCyan; openAccentImage.raycastTarget = false;
            _openAccent = openAccent.gameObject; _openAccent.SetActive(false);

            ResolveLauncherPosition(true);
        }

        // The frame, grip accent/dots, and self-contained position math below intentionally
        // mirror StandaloneLauncherVisual/SuiteUiPositionPolicy (the per-module copied reference
        // implementation, e.g. mods/ErenshorJournal/src/StandaloneLauncherVisual.cs) so the
        // launcher looks and behaves identically across every Forgotten Roads module, without
        // this shared file taking a compile-time dependency on any per-module namespaced type.
        private static void AddLauncherFrame(RectTransform parent)
        {
            AddFrameBlock("FrameTop", parent, new Vector2(0f, LauncherBorder), new Vector2(0f, 1f), new Vector2(1f, 1f));
            AddFrameBlock("FrameBottom", parent, new Vector2(0f, LauncherBorder), new Vector2(0f, 0f), new Vector2(1f, 0f));
            AddFrameBlock("FrameLeft", parent, new Vector2(LauncherBorder, 0f), new Vector2(0f, 0f), new Vector2(0f, 1f));
            AddFrameBlock("FrameRight", parent, new Vector2(LauncherBorder, 0f), new Vector2(1f, 0f), new Vector2(1f, 1f));
        }

        private static void AddFrameBlock(string name, Transform parent, Vector2 size, Vector2 anchorMin, Vector2 anchorMax)
        {
            GameObject go = new GameObject(name, typeof(RectTransform), typeof(Image));
            RectTransform rect = go.GetComponent<RectTransform>(); rect.SetParent(parent, false);
            rect.anchorMin = anchorMin; rect.anchorMax = anchorMax; rect.pivot = new Vector2(0.5f, 0.5f);
            rect.sizeDelta = size; rect.anchoredPosition = Vector2.zero;
            Image image = go.GetComponent<Image>(); image.color = LauncherCyan; image.raycastTarget = false;
        }

        private static void LoadLauncherPosition()
        {
            string key = "ForgottenRoads.StandaloneFallbackUi." + _moduleId + ".launcher";
            _storedLauncherX = InterpretStoredAxis(PlayerPrefs.GetFloat(key + ".x", PositionUnset));
            _storedLauncherY = InterpretStoredAxis(PlayerPrefs.GetFloat(key + ".y", PositionUnset));
            _launcherLastWidth = -1; _launcherLastHeight = -1;
        }

        private static void ResolveLauncherPosition(bool force = false)
        {
            if (_launcher == null) return;
            if (!force && _launcherLastWidth == Screen.width && _launcherLastHeight == Screen.height) return;
            _launcherLastWidth = Screen.width; _launcherLastHeight = Screen.height;
            _launcher.anchoredPosition = new Vector2(
                ResolveAxis(_storedLauncherX, _defaultLauncherX, Screen.width, _launcher.rect.width),
                ResolveAxis(_storedLauncherY, _defaultLauncherY, Screen.height, _launcher.rect.height));
        }

        private static float InterpretStoredAxis(float stored)
        {
            if (!IsFinite(stored) || stored < 0f) return PositionUnset;
            if (stored > 1f) return PositionUnset;
            return stored;
        }

        private static float NormalizeAxis(float pixels, float extent)
        {
            if (extent <= 0f) return PositionUnset;
            return Clamp01(pixels / extent);
        }

        private static float ResolveAxis(float stored, float defaultNormalized, float extent, float size)
        {
            float normalized = stored >= 0f ? stored : defaultNormalized;
            float max = Math.Max(0f, extent - size);
            return Mathf.Clamp(normalized * extent, 0f, max);
        }

        private static float Clamp01(float value) { return value < 0f ? 0f : (value > 1f ? 1f : value); }
        private static bool IsFinite(float value) { return !float.IsNaN(value) && !float.IsInfinity(value); }

        // Panel height baseline (header + header-status gap + status box + status-action gap +
        // bottom margin) with the status box height factored out, so a configured _statusHeight
        // reproduces the exact original 154f baseline at the original 88f default (66+88=154) and
        // shrinks/grows consistently with it everywhere the baseline is used.
        private static float ExpandedPanelHeight()
        {
            return 66f + _statusHeight + (float)Math.Ceiling(Actions.Count / 2.0) * 34f;
        }

        private static void BuildPanel()
        {
            float height = ExpandedPanelHeight();
            _panelObject = MakePanel("Panel", _root.transform, Panel); _panel = Rect(_panelObject, 390f, height); _panelBackground = _panelObject.GetComponent<Image>();
            _panel.anchorMin = _panel.anchorMax = _panel.pivot = new Vector2(.5f, .5f); _panel.anchoredPosition = Vector2.zero;
            RectTransform header = Child("Header", _panel, 390f, 34f, 0f, height - 34f); header.gameObject.AddComponent<Image>().color = Header;
            RectTransform drag = Child("HeaderDrag", header, 306f, 34f, 34f, 0f); drag.gameObject.AddComponent<Image>().color = new Color(0f,0f,0f,0f);
            AddText(drag, _title, 15, TextAnchor.MiddleLeft, 10f); FallbackDragGuard hd = drag.gameObject.AddComponent<FallbackDragGuard>(); hd.Target = _panel;
            RectTransform collapse = Child("Collapse", header, 30f, 24f, 2f, 5f); _collapseButton = AddButton(collapse, string.Empty, delegate { SetCollapsed(!_collapsed); });
            // AddButton already put an Image (a Graphic) on "collapse" for the button's hit target.
            // FallbackChevronGraphic is also Graphic-derived, and Unity allows only one Graphic per
            // GameObject - adding it directly to "collapse" silently fails (AddComponent logs the
            // error and returns null instead of throwing) and the resulting NRE on the next line
            // used to unwind through EnsureBuilt's catch, tearing the whole UI down and rebuilding
            // it - and hitting the same conflict - every single frame. Give it its own child instead.
            EnsureChevron(collapse);
            RectTransform close = Child("Close", header, 30f, 24f, 355f, 5f); AddButton(close, "X", delegate { Close(); });
            RectTransform status = Child("Status", _panel, 370f, _statusHeight, 10f, height - 42f - _statusHeight); _statusText = AddText(status, string.Empty, 12, TextAnchor.UpperLeft, 2f);
            for (int i = 0; i < Actions.Count; i++)
            {
                int row = i / 2, col = i % 2; FallbackAction action = Actions[i];
                RectTransform cell = Child("Action", _panel, 180f, 28f, 10f + col * 190f, height - 72f - _statusHeight - row * 34f);
                FallbackAction captured = action; Buttons.Add(AddButton(cell, action.Label, delegate { try { if (captured.Invoke != null) captured.Invoke(); } catch { } }));
            }
            LoadPanelPosition(); SetCollapsed(false);
        }

        // Idempotent: reuses a valid existing chevron child, repairs (once) a stale/invalid one
        // left over from a previous broken build, and otherwise creates exactly one fresh child.
        // Never adds FallbackChevronGraphic to "owner" itself - see the call site in BuildPanel.
        private static FallbackChevronGraphic EnsureChevron(RectTransform owner)
        {
            if (owner == null) return null;
            Transform existing = owner.Find("Chevron");
            FallbackChevronGraphic graphic = existing == null ? null : existing.GetComponent<FallbackChevronGraphic>();
            if (graphic != null) return graphic;
            if (existing != null) { try { UnityEngine.Object.DestroyImmediate(existing.gameObject); } catch { } }
            RectTransform rect = Child("Chevron", owner, owner.rect.width, owner.rect.height, 0f, 0f);
            graphic = rect.gameObject.AddComponent<FallbackChevronGraphic>();
            graphic.color = Cyan;
            graphic.raycastTarget = false;
            return graphic;
        }

        private static void SetCollapsed(bool collapsed)
        {
            _collapsed = collapsed;
            if (_statusText != null) _statusText.transform.parent.gameObject.SetActive(!collapsed);
            for (int i = 0; i < Buttons.Count; i++) if (Buttons[i] != null) Buttons[i].gameObject.SetActive(!collapsed);

            // Keep the panel RectTransform at its expanded geometry. The header was authored at
            // y=(expandedHeight-34) in that coordinate space. Shrinking the parent to 34px while
            // leaving the header at that authored Y detaches the header from the resized panel and
            // leaves a second 34px Panel Image stranded around the old center -- the blank bar seen
            // live under NEMESIS/FOLLOW/PRACTICE DUEL when collapsed.
            //
            // A disabled parent Image has no raycast target, while the Header has its own Image and
            // buttons. Therefore collapse can be a purely structural visibility change: hide the
            // body children and parent background, keep the stable expanded coordinate space, and
            // preserve the panel's saved/top-edge position with zero collapse/expand jump.
            if (_panelBackground != null) _panelBackground.enabled = !collapsed;

            FallbackChevronGraphic[] arrows = _panel == null ? new FallbackChevronGraphic[0] : _panel.GetComponentsInChildren<FallbackChevronGraphic>(true);
            for (int i = 0; i < arrows.Length; i++)
            {
                arrows[i].Collapsed = collapsed;
                arrows[i].SetVerticesDirty();
            }
        }

        private static void LoadPanelPosition()
        {
            if (_panel == null) return;
            string key = "ForgottenRoads.StandaloneFallbackUi." + _moduleId;
            float x = PlayerPrefs.GetFloat(key + ".x", float.NaN), y = PlayerPrefs.GetFloat(key + ".y", float.NaN);
            if (!float.IsNaN(x) && !float.IsNaN(y) && !float.IsInfinity(x) && !float.IsInfinity(y))
            {
                // A genuinely saved position is preserved exactly (only recovered/clamped if it
                // would otherwise sit off-screen) - never migrated toward the new default.
                _panel.anchoredPosition = new Vector2(Mathf.Clamp(x, -Screen.width * .5f, Screen.width * .5f), Mathf.Clamp(y, -Screen.height * .5f, Screen.height * .5f));
                return;
            }
            _panel.anchoredPosition = ComputeDefaultPanelAnchor();
        }

        // No saved position: the panel opens into the shared default utility workspace below the
        // launcher rail (right-edge aligned with the launcher column) instead of dead screen
        // center, unless the owning module never opted in via ConfigureWorkspaceDefaults - in
        // which case this reproduces the original Vector2.zero (screen-center) default exactly.
        private static Vector2 ComputeDefaultPanelAnchor()
        {
            if (_panelDefaultRightNormalized < 0f || _panelDefaultTopNormalized < 0f || _panel == null) return Vector2.zero;
            float w = _panel.rect.width, h = _panel.rect.height;
            float stagger = _workspaceSlotIndex * PanelSlotStaggerPixels;
            float rightEdgeFromLeft = _panelDefaultRightNormalized * Screen.width - stagger;
            float topEdgeFromBottom = _panelDefaultTopNormalized * Screen.height - stagger;
            float centerXFromLeft = rightEdgeFromLeft - w * 0.5f;
            float centerYFromBottom = topEdgeFromBottom - h * 0.5f;
            float anchoredX = centerXFromLeft - Screen.width * 0.5f;
            float anchoredY = centerYFromBottom - Screen.height * 0.5f;
            float halfW = w * 0.5f, halfH = h * 0.5f;
            anchoredX = Mathf.Clamp(anchoredX, -Screen.width * 0.5f + halfW, Screen.width * 0.5f - halfW);
            anchoredY = Mathf.Clamp(anchoredY, -Screen.height * 0.5f + halfH, Screen.height * 0.5f - halfH);
            return new Vector2(anchoredX, anchoredY);
        }

        internal static void SavePanelPosition(RectTransform target)
        {
            if (target == null) return;
            if (target == _panel)
            {
                string key = "ForgottenRoads.StandaloneFallbackUi." + _moduleId;
                PlayerPrefs.SetFloat(key + ".x", target.anchoredPosition.x); PlayerPrefs.SetFloat(key + ".y", target.anchoredPosition.y); PlayerPrefs.Save();
                return;
            }
            if (target == _launcher)
            {
                string key = "ForgottenRoads.StandaloneFallbackUi." + _moduleId + ".launcher";
                _storedLauncherX = NormalizeAxis(target.anchoredPosition.x, Screen.width);
                _storedLauncherY = NormalizeAxis(target.anchoredPosition.y, Screen.height);
                PlayerPrefs.SetFloat(key + ".x", _storedLauncherX); PlayerPrefs.SetFloat(key + ".y", _storedLauncherY); PlayerPrefs.Save();
                _launcherLastWidth = Screen.width; _launcherLastHeight = Screen.height;
            }
        }

        private static GameObject MakePanel(string name, Transform parent, Color color)
        { GameObject go = new GameObject(name); go.transform.SetParent(parent, false); go.AddComponent<RectTransform>(); go.AddComponent<Image>().color = color; return go; }
        private static RectTransform Rect(GameObject go, float w, float h) { RectTransform r = go.GetComponent<RectTransform>(); r.sizeDelta = new Vector2(w,h); return r; }
        private static RectTransform Child(string name, Transform parent, float w, float h, float x, float y)
        { GameObject go = new GameObject(name); go.transform.SetParent(parent,false); RectTransform r=go.AddComponent<RectTransform>(); r.anchorMin=r.anchorMax=r.pivot=Vector2.zero; r.sizeDelta=new Vector2(w,h); r.anchoredPosition=new Vector2(x,y); return r; }
        private static Text AddText(RectTransform parent, string value, int size, TextAnchor anchor, float inset)
        { RectTransform r=Child("Text",parent,parent.rect.width-inset*2f,parent.rect.height,inset,0f); Text t=r.gameObject.AddComponent<Text>(); t.font=Resources.GetBuiltinResource<Font>("Arial.ttf"); t.text=value; t.fontSize=size; t.alignment=anchor; t.color=Cyan; t.horizontalOverflow=HorizontalWrapMode.Wrap; t.verticalOverflow=VerticalWrapMode.Truncate; t.raycastTarget=false; return t; }
        private static Button AddButton(RectTransform r, string label, UnityEngine.Events.UnityAction action)
        { Image image=r.gameObject.AddComponent<Image>(); image.color=ButtonFill; Button b=r.gameObject.AddComponent<Button>(); ColorBlock c=b.colors; c.normalColor=ButtonFill; c.highlightedColor=Hover; c.pressedColor=Pressed; c.disabledColor=new Color32(8,31,40,145); c.colorMultiplier=1f; b.colors=c; b.onClick.AddListener(action); AddText(r,label,12,TextAnchor.MiddleCenter,3f); return b; }
    }

    internal sealed class FallbackChevronGraphic : MaskableGraphic
    {
        internal bool Collapsed;
        protected override void OnPopulateMesh(VertexHelper vh)
        {
            vh.Clear(); float w = rectTransform.rect.width, h = rectTransform.rect.height; float cx = w * .5f, cy = h * .5f; float t = 2f;
            AddSegment(vh, new Vector2(cx - 6f, cy + (Collapsed ? 3f : -3f)), new Vector2(cx, cy + (Collapsed ? -3f : 3f)), t);
            AddSegment(vh, new Vector2(cx, cy + (Collapsed ? -3f : 3f)), new Vector2(cx + 6f, cy + (Collapsed ? 3f : -3f)), t);
        }
        private void AddSegment(VertexHelper vh, Vector2 a, Vector2 b, float width)
        { Vector2 d = b - a; d.Normalize(); Vector2 n = new Vector2(-d.y, d.x) * width * .5f; int i = vh.currentVertCount; vh.AddVert(a+n, color, new Vector2(0,0)); vh.AddVert(b+n, color, new Vector2(0,0)); vh.AddVert(b-n, color, new Vector2(0,0)); vh.AddVert(a-n, color, new Vector2(0,0)); vh.AddTriangle(i,i+1,i+2); vh.AddTriangle(i,i+2,i+3); }
    }

    internal sealed class FallbackDragGuard : MonoBehaviour, IPointerDownHandler, IBeginDragHandler, IDragHandler, IEndDragHandler, IPointerUpHandler
    {
        private const string OwnerKey = "ForgottenRoads.StandaloneFallbackUi.DragOwners";
        private const string BaselineKey = "ForgottenRoads.StandaloneFallbackUi.DragBaseline";
        private bool _held, _dragging; private Vector2 _offset;
        internal RectTransform Target;
        public void OnPointerDown(PointerEventData e) { if (e.button != PointerEventData.InputButton.Left || Target == null) return; _held=true; Acquire(); RectTransform canvas=Target.parent as RectTransform; RectTransformUtility.ScreenPointToLocalPointInRectangle(canvas,e.position,e.pressEventCamera,out _offset); _offset-=Target.anchoredPosition; }
        public void OnBeginDrag(PointerEventData e) { if(!_held||_dragging)return; _dragging=true; }
        public void OnDrag(PointerEventData e) { if(!_held||Target==null)return; RectTransform canvas=Target.parent as RectTransform; Vector2 p; if(RectTransformUtility.ScreenPointToLocalPointInRectangle(canvas,e.position,e.pressEventCamera,out p)){p-=_offset; float halfW=Target.rect.width*.5f, halfH=Target.rect.height*.5f; if(Target.anchorMin.x<.25f){p.x=Mathf.Clamp(p.x,0f,Mathf.Max(0f,Screen.width-Target.rect.width));p.y=Mathf.Clamp(p.y,0f,Mathf.Max(0f,Screen.height-Target.rect.height));}else{p.x=Mathf.Clamp(p.x,-Screen.width*.5f+halfW,Screen.width*.5f-halfW);p.y=Mathf.Clamp(p.y,-Screen.height*.5f+halfH,Screen.height*.5f-halfH);} Target.anchoredPosition=p;} }
        public void OnEndDrag(PointerEventData e) { StandaloneFallbackUi.SavePanelPosition(Target); Release(); }
        public void OnPointerUp(PointerEventData e) { Release(); }
        private void OnDisable(){Release();} private void OnDestroy(){Release();}
        private void Release(){if(!_held&&!_dragging)return;_held=false;_dragging=false;int owners=Math.Max(0,ProcessOwners()-1);AppDomain.CurrentDomain.SetData(OwnerKey,owners);if(owners==0){bool baseline=false;object stored=AppDomain.CurrentDomain.GetData(BaselineKey);if(stored is bool)baseline=(bool)stored;try{GameData.DraggingUIElement=baseline;}catch{}} }
        private void Acquire(){int owners=ProcessOwners();if(owners==0){bool baseline=false;try{baseline=GameData.DraggingUIElement;}catch{}AppDomain.CurrentDomain.SetData(BaselineKey,baseline);}AppDomain.CurrentDomain.SetData(OwnerKey,owners+1);try{GameData.DraggingUIElement=true;}catch{}}
        private static int ProcessOwners(){object value=AppDomain.CurrentDomain.GetData(OwnerKey);return value is int?Math.Max(0,(int)value):0;}
    }
}
