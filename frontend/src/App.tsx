import { useEffect, useState } from "react";

type HealthResponse = {
  status: string;
  checks?: Record<string, { status: string; detail?: string }>;
};

type ProfileSummary = {
  profile_id: string;
  profile_name: string;
  username: string;
  location_name?: string | null;
  local_birth_datetime?: string | null;
};

export function App() {
  const [health, setHealth] = useState<HealthResponse | null>(null);
  const [profiles, setProfiles] = useState<ProfileSummary[]>([]);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;

    async function bootstrap() {
      try {
        const [healthResponse, profilesResponse] = await Promise.all([
          fetch("/api/v1/health/ready"),
          fetch("/api/v1/profiles")
        ]);

        if (!healthResponse.ok) {
          throw new Error("Health endpoint did not respond successfully.");
        }
        if (!profilesResponse.ok) {
          throw new Error("Profiles endpoint did not respond successfully.");
        }

        const [healthPayload, profilesPayload] = await Promise.all([
          healthResponse.json() as Promise<HealthResponse>,
          profilesResponse.json() as Promise<{ profiles: ProfileSummary[] }>
        ]);

        if (cancelled) {
          return;
        }

        setHealth(healthPayload);
        setProfiles(profilesPayload.profiles);
      } catch (caughtError) {
        if (!cancelled) {
          setError(caughtError instanceof Error ? caughtError.message : "Unknown error");
        }
      }
    }

    bootstrap();
    return () => {
      cancelled = true;
    };
  }, []);

  return (
    <main className="app-shell">
      <section className="hero">
        <div className="eyebrow">Astro Consul</div>
        <h1>Modular monolith, now with a real production backbone.</h1>
        <p>
          The new frontend lives in <code>frontend/</code>, the API is versioned under{" "}
          <code>/api/v1</code>, and the backend is ready to move from file storage toward a
          managed database.
        </p>
      </section>

      <section className="grid">
        <article className="card">
          <h2>Readiness</h2>
          {health ? (
            <>
              <p className={`status ${health.status}`}>Overall status: {health.status}</p>
              <ul>
                {Object.entries(health.checks ?? {}).map(([key, value]) => (
                  <li key={key}>
                    <strong>{key}</strong>: {value.status}
                    {value.detail ? <span> · {value.detail}</span> : null}
                  </li>
                ))}
              </ul>
            </>
          ) : (
            <p>Loading health checks…</p>
          )}
        </article>

        <article className="card">
          <h2>Profiles</h2>
          {profiles.length ? (
            <ul>
              {profiles.map((profile) => (
                <li key={profile.profile_id}>
                  <strong>{profile.profile_name}</strong>
                  <span>@{profile.username}</span>
                  {profile.location_name ? <span>{profile.location_name}</span> : null}
                </li>
              ))}
            </ul>
          ) : (
            <p>No profiles loaded yet.</p>
          )}
        </article>
      </section>

      {error ? (
        <section className="card error-card">
          <h2>Bootstrap Error</h2>
          <p>{error}</p>
        </section>
      ) : null}
    </main>
  );
}

