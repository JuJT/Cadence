declare module "react-native-htmlview" {
  import type { ComponentType, ReactNode } from "react";
  import type { StyleProp, TextStyle, ViewStyle } from "react-native";
  const HTMLView: ComponentType<{
    value: string;
    stylesheet?: Record<string, TextStyle>;
    style?: StyleProp<ViewStyle>;
    onLinkPress?: (value: string) => void;
    renderNode?: (node: { name: string }) => ReactNode | undefined;
    paragraphBreak?: string;
    bullet?: string;
  }>;
  export default HTMLView;
}
