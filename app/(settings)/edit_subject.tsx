import Stack from "@/ui/components/Stack";
import AnimatedPressable from "@/ui/components/AnimatedPressable";
import { Papicons } from "@getpapillon/papicons";
import { useTheme } from "expo-router/react-navigation";
import Typography from "@/ui/components/Typography";
import { CompactGrade } from "@/ui/components/CompactGrade";
import {
  ScrollView,
  TextInput,
  View,
  Platform,
  Modal,
} from "react-native";
import { Colors } from "@/utils/subjects/colors";
import { memo, ReactNode, useCallback, useMemo, useRef, useState } from "react";
import { router, useLocalSearchParams } from "expo-router";
import { useAccountStore } from "@/stores/account";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import TabHeaderTitle from "@/ui/components/TabHeaderTitle";
import ChipButton from "@/ui/components/ChipButton";
import TabHeader from "@/ui/components/TabHeader";
import { useTranslation } from "react-i18next";
import Button from "@/ui/new/Button";
import { UnicodeEmojis } from "@/constants/UnicodeEmojis";
import Animated, { useAnimatedStyle, useSharedValue, withSpring } from "react-native-reanimated";
import { LinearGradient } from "expo-linear-gradient";
import { PapillonZoomIn, PapillonZoomOut } from "@/ui/utils/Transition";
import { ListTouchable } from "@/ui/new/List";
import { LegendList, LegendListRef } from "@legendapp/list";
import { FlashList } from "@shopify/flash-list";
import { trackAdvancedEvent } from "@/utils/logger/analytics";
import { GestureHandlerRootView } from "react-native-gesture-handler";
import SafeHorizontalView from "@/ui/components/SafeHorizontalView";

const EmojiItem = memo(({ item, onPress, isSelected }: {item: string, onPress: (emoji: string) => void, isSelected: boolean}) => {
  const theme = useTheme();
  return (
    <ListTouchable
      onPress={() => onPress(item)}
      style={{
        flex: 1,
        alignItems: "center",
        justifyContent: "center",
      }}
    >
    <View
      style={[
        {
          height: 56,
          width: 56,
          alignItems: "center",
          justifyContent: "center",
          borderRadius: 10,
          marginVertical: 5,
          marginHorizontal: "auto"
        },
        isSelected && {
          backgroundColor: Platform.OS === "ios" ? theme.colors.primary + "20" : theme.colors.primary + "30",
          borderWidth: Platform.OS === "ios" ? 2 : 0,
          borderColor: theme.colors.primary,
        }
      ]}
    >
      <Typography
        style={{
          fontSize: 35,
          lineHeight: 35 * 1.28,
        }}
      >
        {item}
      </Typography>
    </View>
    </ListTouchable>
  );
});

function EmojiPicker({
  onCancel,
  onSelect,
}: {
  onCancel: () => void;
  onSelect: (emoji: string) => void;
}): ReactNode {
  const theme = useTheme();
  const { t } = useTranslation();
  const insets = useSafeAreaInsets();

  const flatListRef = useRef<LegendListRef | null>(null);
  const scale = useSharedValue(1);

  const emojis = useMemo(() => {
    return Object.keys(UnicodeEmojis)
      .map(key => {
        const value = UnicodeEmojis[key];
        const uniqueCodes = [...new Set(value.emojis)];

        return uniqueCodes.length > 0
          ? {
              title: value.icon,
              data: uniqueCodes,
            }
          : null;
      })
      .filter(v => v !== null);
  }, []);

  const flatEmojis = useMemo(() => {
    return emojis.flatMap(section =>
      section.data.map(item => String.fromCodePoint(item))
    );
  }, [emojis]);

  const handleSelect = useCallback(item => {
    setSelectedEmoji(item);
  }, []);

  const [headerHeight, setHeaderHeight] = useState(0);
  const [selectedEmoji, setSelectedEmoji] = useState<string>("😀");

  const emojiContainerStyle = {
    height: 180,
    alignItems: "center",
    justifyContent: "center",
  };

  const [selectedTab, setSelectedTab] = useState(emojis[0].title);

  const selectTab = (tab) => {
    setSelectedTab(tab);
    const section = emojis.find(s => s.title === tab);
    if (section) {
      const index = emojis
        .slice(0, emojis.indexOf(section))
        .reduce((acc, curr) => acc + curr.data.length, 0);
      flatListRef.current?.scrollToOffset({ offset: index * 56, animated: false });
    }
  }

  return (
    <View
      style={{
        flex: 1,
        paddingTop: headerHeight,
        paddingBottom: insets.bottom,
        backgroundColor: theme.colors.background,
      }}
    >
      <TabHeader
        modal={Platform.OS === "ios"}
        onHeightChanged={setHeaderHeight}
        title={
          <TabHeaderTitle
            chevron={false}
            leading={t("Settings_Personalization_Emoji_Picker_Title")}
          />
        }
        trailing={<ChipButton single icon="cross" onPress={onCancel} />}
      />
      <Animated.View
        style={[emojiContainerStyle]}
        key={selectedEmoji + "_preview"}
        entering={PapillonZoomIn}
        exiting={PapillonZoomOut}
      >
        <Typography
          style={{
            fontSize: 100,
            lineHeight: 100 * 1.28,
          }}
        >
          {selectedEmoji}
        </Typography>
      </Animated.View>
      <View
        style={{
          height: 50,
          maxHeight: 50,
          minHeight: 50,
          borderBottomWidth: 0.5,
          borderColor: theme.colors.border,
          paddingHorizontal: 10,
          flexDirection: "row",
          justifyContent: "space-between",
          alignItems: "center",
        }}
      >
        {emojis.map((value, index) => (
          <ListTouchable
            key={index}
            onPress={() => selectTab(value.title)}
            >
          <View
            style={[
              {
                padding: 5,
                height: 50,
                width: 40,
                alignItems: "center",
                justifyContent: "center",
                borderBottomWidth: 3,
                borderColor: "transparent",
              },
              selectedTab === value.title && {
                borderBottomColor: theme.colors.primary,

              },
            ]}
            key={index}
            onPress={() => {
              selectTab(value.title);
            }}
          >
            <Papicons
              name={value.title}
              size={24}
              color={selectedTab === value.title ? theme.colors.primary : theme.colors.text + "7F"}
            />
          </View>
          </ListTouchable>
        ))}
      </View>
      <FlashList
        ref={flatListRef}
        data={flatEmojis}
        numColumns={6}
        drawDistance={900}
        recycleItems
        estimatedItemSize={66}
        keyExtractor={(item, index) => item + index}
        showsVerticalScrollIndicator={false}
        contentContainerStyle={{
          padding: 5,
          paddingBottom: 80,
        }}
        renderItem={({ item }) => (
          <EmojiItem item={item} onPress={handleSelect} isSelected={item === selectedEmoji} />
        )}
      />
      <View
        style={{
          padding: 16,
          position: "absolute",
          bottom: insets.bottom,
          left: 0,
          right: 0,
        }}
      >
        <LinearGradient
          colors={[theme.colors.background + "00", theme.colors.background]}
          style={{
            position: "absolute",
            top: 0,
            left: 0,
            right: 0,
            bottom: 0,
          }}
        />
        <Button
          label={t("Settings_Personalization_Emoji_Picker_SetEmoji")}
          onPress={() => onSelect(selectedEmoji)}
        />
      </View>
    </View>
  );
}

export default function EditSubject() {
  const { colors } = useTheme();
  const insets = useSafeAreaInsets();

  const params = useLocalSearchParams<{ id: string; name?: string; color?: string; emoji?: string }>();

  const [selectedName, setSelectedName] = useState(params.name ?? "");
  const [selectedColor, setSelectedColor] = useState<string>(Colors.find(c => c === params.color) || Colors[0]);
  const [selectedEmoji, setSelectedEmoji] = useState(params.emoji || "📖");
  const [showEmojiPicker, setShowEmojiPicker] = useState(false);

  const AvailableEmojis = [
    "📖",
    "🧮",
    "🌍",
    "🎨",
    "⚽",
    "🎵",
    "🧪",
    "custom",
  ];


  return (
    <View
      style={{
        flex: 1,
        paddingTop: Platform.OS === "android" ? insets.top : 12,
        backgroundColor: colors.background,
      }}
    >
      <SafeHorizontalView base={15}>
        <Stack
          padding={[0, 15]}
          style={{ justifyContent: "space-between", alignItems: "center" }}
          direction={"horizontal"}
        >
          <AnimatedPressable
            accessibilityRole="button"
            accessibilityLabel="Annuler"
            style={{
              padding: 10,
              backgroundColor: colors.text + "10",
              borderRadius: 100,
            }}
            onPress={() => {
              router.back();
            }}
          >
            <Papicons name={"Cross"} size={25} color={colors.text + "7F"} />
          </AnimatedPressable>
          <Typography variant={"title"}>Modifier la matière</Typography>
          <AnimatedPressable
            accessibilityRole="button"
            accessibilityLabel="Enregistrer la matière"
            style={{
              padding: 10,
              backgroundColor: colors.primary,
              borderRadius: 100,
            }}
            onPress={() => {
              const store = useAccountStore.getState();
              const name = selectedName.trim() || params.name || "";
              if (!params.id || !name) return;
              store.setSubjectName(params.id, name);
              store.setSubjectEmoji(params.id, selectedEmoji);
              store.setSubjectColor(params.id, selectedColor);
              trackAdvancedEvent("subject_info_changed", {
                name_changed: name !== params.name,
                emoji_changed: selectedEmoji !== params.emoji,
                color_changed: selectedColor !== params.color,
              });

              router.back();
            }}
          >
            <Papicons name={"Check"} size={25} color={"#FFF"} />
          </AnimatedPressable>
        </Stack>
      </SafeHorizontalView>
      <ScrollView
        keyboardShouldPersistTaps="handled"
        contentContainerStyle={{ paddingTop: 16, paddingBottom: Math.max(insets.bottom, 16) }}
      >
      <Stack hAlign={"center"} pointerEvents={"none"}>
        <CompactGrade
          date={new Date()}
          score={12.6}
          outOf={20}
          skillLevel={[]}
          description={"Exemple d’une note avec la matière"}
          emoji={selectedEmoji}
          title={selectedName || "Matière"}
          color={selectedColor}
        />
      </Stack>

      <Stack gap={10}>
        <SafeHorizontalView base={16}>
          <Stack
            gap={5}
            direction={"horizontal"}
            hAlign={"center"}
            style={{ marginTop: 20 }}
          >
            <Papicons name={"Font"} color={colors.text + "7F"} size={18} />
            <Typography color="secondary">Nom de la matière</Typography>
          </Stack>
        </SafeHorizontalView>
        <SafeHorizontalView base={16}>
          <TextInput
            accessibilityLabel="Nom de la matière"
            placeholder="Nom de la matière"
            placeholderTextColor={`${String(colors.text)}80`}
            selectionColor={colors.primary}
            value={selectedName}
            onChangeText={setSelectedName}
            returnKeyType="done"
            style={{
              alignSelf: "stretch",
              width: "100%",
              minHeight: 52,
              paddingHorizontal: 14,
              paddingVertical: 10,
              borderRadius: 14,
              borderWidth: 1,
              borderColor: colors.border,
              backgroundColor: colors.card,
              color: colors.text,
              fontSize: 17,
            }}
          />
        </SafeHorizontalView>
        <SafeHorizontalView base={16}>
          <Stack
            gap={5}
            direction={"horizontal"}
            hAlign={"center"}
          >
            <Papicons name={"Palette"} color={colors.text + "7F"} size={18} />
            <Typography color="secondary">Couleur</Typography>
          </Stack>
        </SafeHorizontalView>
        <ScrollView
          horizontal
          contentContainerStyle={{
            height: 50,
            alignItems: "center",
          }}
          showsHorizontalScrollIndicator={false}
        >
          <SafeHorizontalView base={16} style={{ flexDirection: "row", alignItems: "center", gap: 10 }}>
            {Colors.map(color => (
              <AnimatedPressable
                key={color}
                style={{
                  width: 40,
                  height: 40,
                  borderRadius: 100,
                  backgroundColor: color,
                  borderWidth: 4,
                  borderColor: "#FFF",
                  shadowColor: "#000",
                  shadowOffset: {
                    width: 0,
                    height: 0,
                  },
                  shadowOpacity: 0.25,
                  justifyContent: "center",
                  alignItems: "center",
                }}
                onPress={() => setSelectedColor(color)}
              >
                {selectedColor === color && (
                  <Papicons name={"Check"} color={"#FFF"} />
                )}
              </AnimatedPressable>
            ))}
          </SafeHorizontalView>
        </ScrollView>
        <SafeHorizontalView base={16}>
          <Stack
            gap={5}
            direction={"horizontal"}
            hAlign={"center"}
          >
            <Papicons name={"Emoji"} color={colors.text + "7F"} size={18} />
            <Typography color="secondary">Emoji</Typography>
          </Stack>
        </SafeHorizontalView>
        <ScrollView
          horizontal
          contentContainerStyle={{
            height: 60,
            alignItems: "center",
          }}
          showsHorizontalScrollIndicator={false}
        >
          <SafeHorizontalView base={16} style={{ flexDirection: "row", alignItems: "center", gap: 10 }}>
            {!AvailableEmojis.includes(selectedEmoji) && (
              <AnimatedPressable
                style={{
                  width: 60,
                  height: 60,
                  borderRadius: 100,
                  backgroundColor: selectedColor + "20",
                  borderWidth: 1,
                  borderColor: colors.border,
                  justifyContent: "center",
                  alignItems: "center",
                }}
              >
                <Typography
                  style={{
                    fontSize: 25,
                    lineHeight: 32,
                  }}
                >
                  {selectedEmoji}
                </Typography>
              </AnimatedPressable>
            )}
            {AvailableEmojis.map(emoji => (
              <AnimatedPressable
                key={emoji}
                style={{
                  width: 60,
                  height: 60,
                  borderRadius: 100,
                  backgroundColor:
                    selectedColor + (selectedEmoji === emoji ? "20" : "00"),
                  borderWidth: 1,
                  borderColor: colors.border,
                  justifyContent: "center",
                  alignItems: "center",
                }}
                onPress={() => {
                  if (emoji === "custom") {
                    setShowEmojiPicker(true);
                  } else {
                    setSelectedEmoji(emoji);
                  }
                }}
              >
                {emoji === "custom" ? (
                  <Papicons name={"Emoji"} color={colors.text + "7F"} size={25} />
                ) : (
                  <Typography
                    style={{
                      fontSize: 25,
                      lineHeight: 32,
                    }}
                  >
                    {emoji}
                  </Typography>
                )}
              </AnimatedPressable>
            ))}
          </SafeHorizontalView>
        </ScrollView>
      </Stack>
      </ScrollView>
      <Modal
        presentationStyle={"formSheet"}
        animationType={"slide"}
        visible={showEmojiPicker}
        onRequestClose={() => setShowEmojiPicker(false)}
      >
        <GestureHandlerRootView style={{ flex: 1 }}>
        <EmojiPicker
          onCancel={() => setShowEmojiPicker(false)}
          onSelect={emoji => {
            setSelectedEmoji(emoji);
            setShowEmojiPicker(false);
          }}
        />
        </GestureHandlerRootView>
      </Modal>
    </View>
  );
};
