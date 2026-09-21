export const LANGUAGES: readonly string[];
export function setLanguage(code: unknown): string;
export function language(): string;
export function t(key: string, params?: Record<string, string | number>): string;
export function texts(code: string): Record<string, string> | undefined;
