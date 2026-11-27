import { Link } from 'expo-router';
import { useTheme } from 'expo-router/react-navigation';
import { Pressable, StyleSheet } from 'react-native';

import { HomeCardContent, type HomeHeaderButtonItem } from '@/components/HomeCardContent';

export default function HomeHeaderButton({ item }: { item: HomeHeaderButtonItem }) {
  const { colors } = useTheme();
  return (
    <Link asChild href={{ pathname: item.route, params: item.params }}>
      <Pressable accessibilityRole="button" accessibilityLabel={`${item.title}, ${item.description}`}
        android_ripple={{ color: colors.border }} style={[styles.card, { backgroundColor: colors.card }]}>
        <HomeCardContent item={item} />
      </Pressable>
    </Link>
  );
}

const styles = StyleSheet.create({
  card: { flex: 1, minWidth: 0, minHeight: 60, flexDirection: 'row', alignItems: 'center', gap: 8,
    padding: 10, borderRadius: 20, elevation: 2, overflow: 'hidden' },
});
