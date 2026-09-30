{{flutter_js}}
{{flutter_build_config}}

// All render resources come from the same app, including the local bundle.
_flutter.loader.load({
  config: {
    canvasKitBaseUrl: new URL('canvaskit/', document.baseURI).href,
    fontFallbackBaseUrl: new URL('font-fallback/', document.baseURI).href,
  },
});
