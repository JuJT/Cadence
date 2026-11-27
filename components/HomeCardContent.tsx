import { Papicons } from '@getpapillon/papicons';
import { Image, StyleSheet, View, type ImageSourcePropType } from 'react-native';

import Typography from '@/ui/components/Typography';

export interface HomeHeaderButtonItem {
  title: string;
  icon: string;
  color: string;
  description: string;
  route: string;
  params?: Record<string, string>;
  image?: ImageSourcePropType;
}

export function HomeCardContent({ item }: { item: HomeHeaderButtonItem }) {
  return (
    <>
      <View style={styles.icon} accessible={false}>
        {item.image ? (
          <Image source={item.image} resizeMode="contain" style={styles.image} accessible={false} />
        ) : (
          <Papicons name={item.icon} color={item.color} size={23} />
        )}
      </View>
      <View style={styles.text}>
        <Typography variant="body2" weight="bold" numberOfLines={2}>{item.title}</Typography>
        <Typography variant="caption" color="secondary" numberOfLines={2}>{item.description}</Typography>
      </View>
    </>
  );
}

const styles = StyleSheet.create({
  icon: { width: 28, height: 28, flexShrink: 0, alignItems: 'center', justifyContent: 'center' },
  image: { width: 26, height: 26 },
  text: { flex: 1, minWidth: 0, gap: 2 },
});
