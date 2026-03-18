interface B3LogoProps {
  size?: "sm" | "md";
  className?: string;
}

export default function B3Logo({ size = "md", className }: B3LogoProps) {
  const fontSize = size === "sm" ? "0.95rem" : "1.15rem";

  return (
    <span
      className={`b3-wordmark ${className ?? ""}`}
      style={{ fontSize }}
    >
      <span className="b3-wordmark__big">big</span>
      <span className="b3-wordmark__3">3</span>
      <span className="b3-wordmark__me">.me</span>
    </span>
  );
}
