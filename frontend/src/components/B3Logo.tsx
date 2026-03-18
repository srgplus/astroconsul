interface B3LogoProps {
  size?: number;
  className?: string;
}

export default function B3Logo({ size = 28, className }: B3LogoProps) {
  return (
    <svg
      className={className}
      viewBox="0 0 32 32"
      width={size}
      height={size}
      xmlns="http://www.w3.org/2000/svg"
    >
      <defs>
        <linearGradient id="b3-bg-grad" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0%" stopColor="#2a2a2e" />
          <stop offset="100%" stopColor="#1c1c1e" />
        </linearGradient>
      </defs>
      <rect width="32" height="32" rx="8" fill="url(#b3-bg-grad)" />
      <rect
        x="0.5"
        y="0.5"
        width="31"
        height="31"
        rx="7.5"
        fill="none"
        stroke="rgba(255,255,255,0.12)"
        strokeWidth="1"
      />
      <text
        x="16"
        y="22.5"
        textAnchor="middle"
        fontFamily="system-ui, -apple-system, sans-serif"
        fontSize="18"
      >
        <tspan fill="#f5f5f7" fontWeight="300">b</tspan>
        <tspan fill="#4ecf8b" fontWeight="700">3</tspan>
      </text>
    </svg>
  );
}
