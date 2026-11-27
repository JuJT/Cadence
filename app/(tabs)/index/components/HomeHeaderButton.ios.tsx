import { useTheme } from "expo-router/react-navigation";
import { LiquidGlassView } from '@sbaiahmed1/react-native-blur';
import React from 'react';
import { Pressable, StyleSheet, View } from 'react-native';
import adjust from "@/utils/adjustColor";

import { Link } from 'expo-router';
import { LinearGradient } from 'expo-linear-gradient';

import { HomeCardContent, type HomeHeaderButtonItem } from '@/components/HomeCardContent';

interface HomeHeaderButtonProps {
  item: HomeHeaderButtonItem;
}

const HomeHeaderButton: React.FC<HomeHeaderButtonProps> = ({ item }) => {
  const theme = useTheme();
  const { colors } = theme;

  return (
    <Link
      asChild
      href={{
        pathname: item.route,
        params: item.params,
      }}
    >
        <Pressable
          accessibilityRole="button"
          accessibilityLabel={`${item.title}, ${item.description}`}
          style={({ pressed }) => [styles.headerBtn, pressed && { opacity: 0.78 }]}
        >
          <View pointerEvents="none" style={[StyleSheet.absoluteFill, styles.background]}>
            <LiquidGlassView glassOpacity={0.4} glassTintColor={adjust(item.color, theme.dark ? -0.8 : 0.9)}
              glassType="regular" style={{ flex: 1, borderRadius: 22 }} />
            <LinearGradient colors={[String(colors.background) + (theme.dark ? "00" : "99"), String(colors.background) + (theme.dark ? "99" : "00")]}
              style={[StyleSheet.absoluteFill, { borderRadius: 22 }]} />
          </View>
          <HomeCardContent item={item} />
        </Pressable>
    </Link>
  );
};

const styles = StyleSheet.create({
  headerBtn: {
    flex: 1,
    minWidth: 0,
    minHeight: 60,
    flexDirection: "row",
    borderCurve: "circular",
    borderRadius: 20,
    padding: 10,
    gap: 8,
    alignItems: "center",
  },
  background: { borderRadius: 20, overflow: 'hidden' },
});

export default HomeHeaderButton;
