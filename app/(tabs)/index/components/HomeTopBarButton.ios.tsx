import React from 'react';
import { Pressable, StyleSheet, View } from 'react-native';
import { LiquidGlassView } from '@sbaiahmed1/react-native-blur';
import Icon from '@/ui/components/Icon';
import { Papicons } from '@getpapillon/papicons';
import { Link } from 'expo-router';

interface HomeTopBarButtonProps {
  icon: string;
  route?: string;
}

const HomeTopBarButton: React.FC<HomeTopBarButtonProps> = ({ icon, route }) => {
  return (
    <Link asChild href={route ?? "/(features)/soon"}>
      <Pressable accessibilityRole="button" accessibilityLabel={icon === 'palette' ? 'Fond d’écran' : 'Réglages'}
        style={({ pressed }) => [styles.button, pressed && { opacity: 0.75 }]}>
        <View pointerEvents="none" style={StyleSheet.absoluteFill}>
          <LiquidGlassView glassType="clear" glassOpacity={0} style={styles.glass} />
        </View>
        <Icon size={26} fill='white'>
          <Papicons name={icon} />
        </Icon>
      </Pressable>
    </Link>
  );
};

export default HomeTopBarButton;

const styles = StyleSheet.create({
  button: { width: 44, height: 44, alignItems: 'center', justifyContent: 'center' },
  glass: { flex: 1, borderRadius: 22 },
});
