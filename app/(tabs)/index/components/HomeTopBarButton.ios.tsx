import React from 'react';
import { Pressable, StyleSheet, View } from 'react-native';
import { LiquidGlassView } from '@sbaiahmed1/react-native-blur';
import Icon from '@/ui/components/Icon';
import { Papicons } from '@getpapillon/papicons';
import { useRouter } from 'expo-router';

interface HomeTopBarButtonProps {
  icon: string;
  route?: string;
}

const HomeTopBarButton: React.FC<HomeTopBarButtonProps> = ({ icon, route }) => {
  const router = useRouter();
  return (
    <Pressable accessibilityRole="button" accessibilityLabel={icon === 'palette' ? 'Fond d’écran' : 'Réglages'}
      onPress={() => router.navigate(route ?? '/(features)/soon')}
      style={({ pressed }) => [styles.button, pressed && styles.pressed]}>
      <View pointerEvents="none" style={StyleSheet.absoluteFill}>
        <LiquidGlassView glassType="clear" glassOpacity={0} style={styles.glass} />
      </View>
      <Icon size={26} fill='white'>
        <Papicons name={icon} />
      </Icon>
    </Pressable>
  );
};

export default HomeTopBarButton;

const styles = StyleSheet.create({
  button: { width: 44, height: 44, alignItems: 'center', justifyContent: 'center' },
  pressed: { opacity: 0.75 },
  glass: { flex: 1, borderRadius: 22 },
});
