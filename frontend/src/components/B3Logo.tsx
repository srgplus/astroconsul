interface B3LogoProps {
  size?: "sm" | "md";
  className?: string;
}

export default function B3Logo({ size = "md", className }: B3LogoProps) {
  const fontSize = size === "sm" ? "0.95rem" : "1.15rem";

  return (
    <span
      className={className}
      style={{
        fontFamily: "'Space Grotesk', sans-serif",
        fontSize,
        letterSpacing: "-1px",
        lineHeight: 1,
        whiteSpace: "nowrap",
      }}
    >
      <span style={{ fontWeight: 300, color: "#f5f5f7" }}>big</span>
      <span style={{ fontWeight: 700, color: "#f5f5f7" }}>3</span>
      <span style={{ fontWeight: 400, fontSize: "0.65em", letterSpacing: 0, color: "#666" }}>.me</span>
    </span>
  );
}
