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

        private static string _moduleId, _title, _guide;
        private static float _launcherY;
        private static Func<string> _status;
        private static readonly List<FallbackAction> Actions = new List<FallbackAction>();
        private static IAuraSubscriber<string> _hub;
        private static float _nextHubProbe;
        private static bool _hubUsable;
        private static GameObject _root, _launcherObject, _panelObject;
        private static RectTransform _launcher, _panel;
        private static Text _statusText;
        private static readonly List<Button> Buttons = new List<Button>();
        private static bool _open;
        private static bool _collapsed;
        private static Button _collapseButton;

        internal static bool IsOpen { get { return _open; } }

        internal static void Initialize(LunarisPlugin owner, string moduleId, string title,
            string guide, float launcherY, Func<string> status, params FallbackAction[] actions)
        {
            Dispose();
            _moduleId = moduleId ?? string.Empty; _title = title ?? "MOD"; _guide = guide ?? string.Empty;
            _launcherY = launcherY; _status = status;
            if (actions != null) Actions.AddRange(actions);
            try { if (owner != null) _hub = owner.IPCAuraSubscriber<string>(HubEndpoint); } catch { _hub = null; }
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
            _launcherObject.SetActive(!_hubUsable);
            _panelObject.SetActive(_open);
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
            _root = _launcherObject = _panelObject = null; _launcher = _panel = null; _statusText = null;
            Buttons.Clear(); Actions.Clear(); _hub = null; _hubUsable = false; _nextHubProbe = 0f; _open = false; _collapsed = false; _collapseButton = null;
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
            _launcherObject = MakePanel("Launcher", _root.transform, Panel); _launcher = Rect(_launcherObject, 154f, 32f);
            _launcher.anchorMin = _launcher.anchorMax = _launcher.pivot = Vector2.zero; _launcher.anchoredPosition = new Vector2(18f, _launcherY);
            RectTransform grip = Child("Grip", _launcher, 20f, 32f, 0f, 0f); Image gi = grip.gameObject.AddComponent<Image>(); gi.color = Header;
            FallbackDragGuard gd = grip.gameObject.AddComponent<FallbackDragGuard>(); gd.Target = _launcher;
            for (int i = 0; i < 3; i++) { RectTransform dot = Child("Dot", grip, 3f, 3f, 8.5f, 8f + i * 7f); Image di = dot.gameObject.AddComponent<Image>(); di.color = Cyan; }
            RectTransform button = Child("Open", _launcher, 134f, 32f, 20f, 0f); AddButton(button, _title, delegate { Toggle(); });
        }

        private static void BuildPanel()
        {
            float height = 154f + (float)Math.Ceiling(Actions.Count / 2.0) * 34f;
            _panelObject = MakePanel("Panel", _root.transform, Panel); _panel = Rect(_panelObject, 390f, height);
            _panel.anchorMin = _panel.anchorMax = _panel.pivot = new Vector2(.5f, .5f); _panel.anchoredPosition = Vector2.zero;
            RectTransform header = Child("Header", _panel, 390f, 34f, 0f, height - 34f); header.gameObject.AddComponent<Image>().color = Header;
            RectTransform drag = Child("HeaderDrag", header, 306f, 34f, 34f, 0f); drag.gameObject.AddComponent<Image>().color = new Color(0f,0f,0f,0f);
            AddText(drag, _title, 15, TextAnchor.MiddleLeft, 10f); FallbackDragGuard hd = drag.gameObject.AddComponent<FallbackDragGuard>(); hd.Target = _panel;
            RectTransform collapse = Child("Collapse", header, 30f, 24f, 2f, 5f); _collapseButton = AddButton(collapse, string.Empty, delegate { SetCollapsed(!_collapsed); });
            FallbackChevronGraphic chevron = collapse.gameObject.AddComponent<FallbackChevronGraphic>(); chevron.color = Cyan;
            RectTransform close = Child("Close", header, 30f, 24f, 355f, 5f); AddButton(close, "X", delegate { Close(); });
            RectTransform status = Child("Status", _panel, 370f, 88f, 10f, height - 130f); _statusText = AddText(status, string.Empty, 12, TextAnchor.UpperLeft, 2f);
            for (int i = 0; i < Actions.Count; i++)
            {
                int row = i / 2, col = i % 2; FallbackAction action = Actions[i];
                RectTransform cell = Child("Action", _panel, 180f, 28f, 10f + col * 190f, height - 160f - row * 34f);
                FallbackAction captured = action; Buttons.Add(AddButton(cell, action.Label, delegate { try { if (captured.Invoke != null) captured.Invoke(); } catch { } }));
            }
            LoadPanelPosition(); SetCollapsed(false);
        }

        private static void SetCollapsed(bool collapsed)
        {
            _collapsed = collapsed;
            if (_statusText != null) _statusText.transform.parent.gameObject.SetActive(!collapsed);
            for (int i = 0; i < Buttons.Count; i++) if (Buttons[i] != null) Buttons[i].gameObject.SetActive(!collapsed);
            if (_panel != null) _panel.sizeDelta = new Vector2(_panel.sizeDelta.x, collapsed ? 34f : 154f + (float)Math.Ceiling(Actions.Count / 2.0) * 34f);
            FallbackChevronGraphic[] arrows = _panel == null ? new FallbackChevronGraphic[0] : _panel.GetComponentsInChildren<FallbackChevronGraphic>(true);
            for (int i = 0; i < arrows.Length; i++) arrows[i].Collapsed = collapsed;
        }

        private static void LoadPanelPosition()
        {
            if (_panel == null) return;
            string key = "ForgottenRoads.StandaloneFallbackUi." + _moduleId;
            float x = PlayerPrefs.GetFloat(key + ".x", float.NaN), y = PlayerPrefs.GetFloat(key + ".y", float.NaN);
            if (!float.IsNaN(x) && !float.IsNaN(y) && !float.IsInfinity(x) && !float.IsInfinity(y)) _panel.anchoredPosition = new Vector2(Mathf.Clamp(x, -Screen.width * .5f, Screen.width * .5f), Mathf.Clamp(y, -Screen.height * .5f, Screen.height * .5f));
        }

        internal static void SavePanelPosition(RectTransform target)
        {
            if (target == null || target != _panel) return;
            string key = "ForgottenRoads.StandaloneFallbackUi." + _moduleId;
            PlayerPrefs.SetFloat(key + ".x", target.anchoredPosition.x); PlayerPrefs.SetFloat(key + ".y", target.anchoredPosition.y); PlayerPrefs.Save();
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
