defmodule Risteys.Repo.Migrations.ModifyCodewasCodes do
  use Ecto.Migration

  def change do
    alter table(:codewas_codes) do
      modify(:description, :text, null: true, from: {:string, null: false})
    end
  end
end
