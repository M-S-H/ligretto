defmodule Ligretto.Repo do
  use Ecto.Repo,
    otp_app: :ligretto,
    adapter: Ecto.Adapters.Postgres
end
