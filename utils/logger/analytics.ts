type Segmentation = Record<string, string | number | boolean>;

// These hooks preserve upstream callers without collecting telemetry in Cadenza.
export function trackOptionalEvent(_event: string, _segmentation?: Segmentation): void {}
export function trackAdvancedEvent(_event: string, _segmentation?: Segmentation): void {}
