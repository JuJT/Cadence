import { ProgressiveBlurView } from '@sbaiahmed1/react-native-blur';
import React from 'react';
import { Platform, View } from 'react-native';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';

import Stack from '@/ui/components/Stack';

import HomeTopBarButton from '../components/HomeTopBarButton';
import UserProfile from './UserProfile';

const HomeTopBar = ({ height = 56, loading }: { height?: number, loading?: boolean }) => {
  const insets = useSafeAreaInsets();

  return (
    <>
      {Platform.OS === "ios" && (
        <View pointerEvents="none"
          style={{
            position: "absolute",
            top: 0,
            left: 0,
            right: 0,
            height: height + insets.top,
            zIndex: 10,
            overflow: "hidden",
          }}
        >
          <ProgressiveBlurView
            blurAmount={10}
            blurType="systemUltraThinMaterial"
            direction="blurredTopClearBottom"
            startOffset={0}
            reducedTransparencyFallbackColor="#00000000"
            style={{ width: "100%", height: "100%" }}
          />
        </View>
      )}

      <SafeAreaView
        pointerEvents="box-none"
        edges={['left', 'right']}
        style={{
          height: height,
          position: "absolute",
          top: insets.top + (insets.right > 10 ? 10 : 0),
          left: 0,
          right: 0,
          paddingHorizontal: 16,
          zIndex: 11,
          justifyContent: "center",
          alignItems: 'center',
        }}
      >
        <View pointerEvents="box-none"
          style={{
            width: "100%",
            maxWidth: 670,
            alignItems: "center",
            flexDirection: "row",
            gap: 16,
          }}
        >
          <UserProfile loading={loading} />

          <Stack
            direction="horizontal"
            hAlign="center"
            vAlign="end"
            gap={7}
            inline
          >
            <HomeTopBarButton
              icon="palette"
              route="/(modals)/wallpaper"
            />
            <HomeTopBarButton
              icon="gears"
              route="/(settings)/settings"
            />
          </Stack>
        </View>
      </SafeAreaView>
    </>
  );
};

export default HomeTopBar;
