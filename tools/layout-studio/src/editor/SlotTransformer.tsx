import { useEffect, useRef } from "react";
import Konva from "konva";
import { Transformer } from "react-konva";

interface Props {
  selectedNode: Konva.Group | null;
}

/** § 12 — resize from the 4 corners (plus the 4 edges, Konva's default enabled-anchors set).
 * Geometry itself is read back out of the node in `LayoutCanvas`'s `onTransformEnd` handler
 * (never persisted as Konva's own `scaleX`/`scaleY` — § 5: "Không lưu scaleX/scaleY của Konva vào
 * JSON"), which is also where scale gets reset back to `1` after every resize. */
export function SlotTransformer({ selectedNode }: Props) {
  const transformerRef = useRef<Konva.Transformer>(null);

  useEffect(() => {
    const transformer = transformerRef.current;
    if (!transformer) return;
    if (selectedNode) {
      transformer.nodes([selectedNode]);
    } else {
      transformer.nodes([]);
    }
    transformer.getLayer()?.batchDraw();
  }, [selectedNode]);

  return (
    <Transformer
      ref={transformerRef}
      rotateEnabled={false}
      flipEnabled={false}
      boundBoxFunc={(_oldBox, newBox) => {
        if (newBox.width < 8 || newBox.height < 8) return _oldBox;
        return newBox;
      }}
    />
  );
}
