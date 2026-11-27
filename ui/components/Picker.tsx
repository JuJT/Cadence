import { Button, Host, Menu } from "@expo/ui/swift-ui";
import { disabled as nativeDisabled, tint } from "@expo/ui/swift-ui/modifiers";
import { Papicons } from "@getpapillon/papicons";
import { useTheme } from "expo-router/react-navigation";
import { Platform, View } from "react-native";

import ActionMenu from "./ActionMenu";
import Typography from "../new/Typography";

type PickerProps = {
  options: string[];
  selectedIndex: number;
  onValueChange: (index: number) => void;
  disabled?: boolean;
};

export default function Picker({ options, selectedIndex, onValueChange, disabled }: PickerProps) {
  const { colors } = useTheme();
  const label = options[selectedIndex] ?? "Choisir";
  const isDisabled = Boolean(disabled || options.length === 0);

  if (Platform.OS === "ios") {
    return (
      <Host matchContents style={{ minHeight: 44, justifyContent: "center" }}>
        <Menu
          label={label}
          systemImage="chevron.down"
          modifiers={[tint(String(colors.primary)), nativeDisabled(isDisabled)]}
        >
          {options.map((option, index) => (
            <Button
              key={index}
              label={option}
              systemImage={index === selectedIndex ? "checkmark" : undefined}
              onPress={() => onValueChange(index)}
            />
          ))}
        </Menu>
      </Host>
    );
  }

  return (
    <View pointerEvents={isDisabled ? "none" : "auto"}>
      <ActionMenu
        actions={options.map((option, index) => ({
          id: String(index),
          title: option,
          state: index === selectedIndex ? "on" : "off",
        }))}
        onPressAction={({ nativeEvent }) => onValueChange(Number(nativeEvent.event))}
      >
        <View style={{ flexDirection: "row", alignItems: "center", gap: 4 }}>
          <Typography variant="body1" weight="semibold" color="primary">{label}</Typography>
          <Papicons name="ChevronDown" size={16} color={String(colors.primary)} />
        </View>
      </ActionMenu>
    </View>
  );
}
