import React, { useCallback, useEffect, useRef, useState } from "react";
import { createRoot } from "react-dom/client";
import { Excalidraw, exportToSvg, serializeAsJSON } from "@excalidraw/excalidraw";
import "../node_modules/@excalidraw/excalidraw/dist/prod/index.css";
import "./whiteboard.css";

// Excalidraw fetches its fonts relative to this path.
window.EXCALIDRAW_ASSET_PATH = new URL(".", location.href).href;

const post = (message) => {
  window.webkit?.messageHandlers?.perch?.postMessage(message);
  window.__perchMessages?.push(message);
};

/** Base64-inflates the scene from an .excalidraw.svg file, using Excalidraw's own loader. */
async function sceneFromFile({ name, text, sceneJSON }) {
  if (sceneJSON) return JSON.parse(sceneJSON);
  return JSON.parse(text);
}

function Board() {
  const [initial, setInitial] = useState(null);
  const file = useRef(null);
  const api = useRef(null);
  const lastSaved = useRef("");
  const timer = useRef(null);

  const signature = (elements) =>
    JSON.stringify(elements.map((element) => [element.id, element.version, element.isDeleted]));

  const save = useCallback(async (elements, appState, files) => {
    if (!file.current) return;
    if (file.current.name.toLowerCase().endsWith(".svg")) {
      const svg = await exportToSvg({
        elements,
        files,
        exportPadding: 10,
        appState: { ...appState, exportEmbedScene: true, exportBackground: true },
      });
      post({ type: "whiteboardSave", content: svg.outerHTML });
    } else {
      post({ type: "whiteboardSave", content: serializeAsJSON(elements, appState, files, "local") });
    }
  }, []);

  useEffect(() => {
    window.Perch = {
      async load(descriptor) {
        const scene = await sceneFromFile(descriptor);
        file.current = descriptor;
        lastSaved.current = signature(scene.elements ?? []);
        const dark = matchMedia("(prefers-color-scheme: dark)").matches;
        const data = {
          elements: scene.elements ?? [],
          files: scene.files ?? {},
          appState: { ...(scene.appState ?? {}), collaborators: new Map(), theme: dark ? "dark" : "light" },
          scrollToContent: true,
        };
        if (api.current) api.current.updateScene(data);
        setInitial(data);
        return true;
      },
      flush({ force = false } = {}) {
        if (!api.current) return;
        clearTimeout(timer.current);
        const elements = api.current.getSceneElementsIncludingDeleted();
        if (force || signature(elements) !== lastSaved.current) {
          lastSaved.current = signature(elements);
          return save(elements, api.current.getAppState(), api.current.getFiles());
        }
      },
    };
    post({ type: "ready" });
  }, [save]);

  if (!initial) return <div className="loading">Opening whiteboard…</div>;
  return (
    <Excalidraw
      excalidrawAPI={(value) => { api.current = value; }}
      initialData={initial}
      onChange={(elements, appState, files) => {
        // Only real edits save, so opening a board never changes its file.
        const allElements = api.current?.getSceneElementsIncludingDeleted() ?? elements;
        if (signature(allElements) === lastSaved.current) return;
        clearTimeout(timer.current);
        timer.current = setTimeout(() => {
          const latest = api.current.getSceneElementsIncludingDeleted();
          lastSaved.current = signature(latest);
          save(latest, api.current.getAppState(), api.current.getFiles());
        }, 800);
      }}
    />
  );
}

createRoot(document.getElementById("root")).render(<Board />);
