defmodule Risteys.FGEndpoint.Correlation do
  use Ecto.Schema
  import Ecto.Changeset

  schema "correlations" do
    field :fg_endpoint_a_id, :id
    field :fg_endpoint_b_id, :id

    field :case_overlap_percent, :float
    field :case_overlap_N, :integer
    field :shared_of_a, :float
    field :shared_of_b, :float
    field :coloc_gws_hits_same_dir, :integer
    field :coloc_gws_hits_opp_dir, :integer
    field :rel_beta_same_dir, :float
    field :rel_beta_opp_dir, :float
    field :variants_same_dir, {:array, :string}
    field :variants_opp_dir, {:array, :string}

    timestamps()
  end

  @doc false
  def changeset(correlation, attrs) do
    correlation
    |> cast(attrs, [
      :fg_endpoint_a_id,
      :fg_endpoint_b_id,
      :case_overlap_percent,
      :case_overlap_N,
      :shared_of_a,
      :shared_of_b,
      :coloc_gws_hits_same_dir,
      :coloc_gws_hits_opp_dir,
      :rel_beta_same_dir,
      :rel_beta_opp_dir,
      :variants_same_dir,
      :variants_opp_dir,
    ])
    |> validate_required([
      :fg_endpoint_a_id,
      :fg_endpoint_b_id,
    ])
    |> validate_number(:case_overlap_N, greater_than_or_equal_to: 0)
    |> validate_number(:case_overlap_percent, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 100.0)
    |> validate_number(:shared_of_a, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_number(:shared_of_b, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> unique_constraint(:fg_endpoint_a_id, name: :fg_endpoint_a_b)
  end
end
