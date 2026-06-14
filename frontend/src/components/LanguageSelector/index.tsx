'use client';

import { getLanguageFlag, getLanguageName } from '@/lib/utils';

const LANGUAGES = [
  'en', 'es', 'fr', 'de', 'it', 'pt', 'ru', 'zh',
  'ja', 'ko', 'ar', 'hi', 'ur', 'tr', 'nl', 'pl',
  'sv', 'no', 'da', 'fi',
];

interface Props {
  value: string;
  onChange: (code: string) => void;
  label?: string;
  disabled?: boolean;
}

export function LanguageSelector({ value, onChange, label, disabled }: Props) {
  return (
    <div className="flex flex-col gap-1.5">
      {label && (
        <label className="text-xs font-medium text-surface-400 uppercase tracking-wider">
          {label}
        </label>
      )}
      <div className="relative">
        <select
          value={value}
          onChange={e => onChange(e.target.value)}
          disabled={disabled}
          className="
            w-full appearance-none bg-surface-800 border border-surface-600
            text-white rounded-xl px-4 py-3 pr-10
            focus:outline-none focus:ring-2 focus:ring-brand-500 focus:border-transparent
            disabled:opacity-50 disabled:cursor-not-allowed
            transition-colors cursor-pointer text-sm
          "
        >
          {LANGUAGES.map(code => (
            <option key={code} value={code}>
              {getLanguageFlag(code)} {getLanguageName(code)}
            </option>
          ))}
        </select>
        <div className="pointer-events-none absolute inset-y-0 right-3 flex items-center">
          <svg className="w-4 h-4 text-surface-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
          </svg>
        </div>
      </div>
      <div className="text-xs text-surface-500">
        {getLanguageFlag(value)} {getLanguageName(value)} selected
      </div>
    </div>
  );
}
