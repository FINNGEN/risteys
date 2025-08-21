defmodule Risteys.FGEndpoint.Definition do
  use Ecto.Schema
  import Ecto.Changeset

  schema "fg_endpoint_definitions" do
    field :name, :string

    field :tags, :string
    field :level, :string
    field :omit, :string

    # Core/non-core endpoint info
    field :is_core, :boolean
    field :reason_non_core, :string
    field :selected_core_id, :id

    field :longname, :string
    field :sex, :string
    field :include, :string
    field :pre_conditions, :string
    field :conditions, :string

    # Definitions of specific controls
    field :control_exclude, :string
    field :control_preconditions, :string
    field :control_conditions, :string

    # raw, unprocessed Outpat ICD_10
    field :outpat_icd, :string
    field :outpat_oper, :string
    field :hd_mainonly, :string
    field :hd_icd_10_atc, :string
    # raw, unprocessed HD_ICD_10
    field :hd_icd_10, :string
    # raw, unprocessed HD_ICD_9
    field :hd_icd_9, :string
    field :hd_icd_8, :string
    # raw, unprocessed excl:HD_ICD_10
    field :hd_icd_10_excl, :string
    field :hd_icd_9_excl, :string
    field :hd_icd_8_excl, :string
    field :cod_mainonly, :string
    # raw, unprocessed COD_ICD_10
    field :cod_icd_10, :string
    # raw, unprocessed COD_ICD_9
    field :cod_icd_9, :string
    field :cod_icd_8, :string
    # raw, unprocessed excl:COD_ICD_10
    field :cod_icd_10_excl, :string
    field :cod_icd_9_excl, :string
    field :cod_icd_8_excl, :string
    field :oper_nom, :string
    field :oper_hl, :string
    field :oper_hp1, :string
    field :oper_hp2, :string
    field :kela_reimb, :string
    # raw, unprocessed Kela ICD_10
    field :kela_reimb_icd, :string
    field :kela_atc_needother, :string
    field :kela_atc, :string
    field :kela_vnro_needother, :string
    field :kela_vnro, :string
    field :canc_topo, :string
    field :canc_topo_excl, :string
    field :canc_morph, :string
    field :canc_morph_excl, :string
    field :canc_behav, :string
    field :special, :string
    field :version, :string
    field :parent, :string
    field :latin, :string

    field :category, :string
    field :ontology, {:map, {:array, :string}}
    # Description is populated from the ontology
    field :description, :string

    # Genome-wide significant hits
    field :gws_hits, :integer

    # Upset plot and table info
    field :status_upset_plot_fr, :string
    field :status_upset_table_fr, :string
    field :status_upset_plot_fg, :string
    field :status_upset_table_fg, :string

    # exclusion reason for FinRegistry enpoints. nil = not exluded
    field :fr_excl, :string

    many_to_many :icd10s, Risteys.Icd10,
      join_through: Risteys.FGEndpoint.DefinitionICD10,
      # Delete ICD-10s not included in the update
      on_replace: :delete

    many_to_many :icd9s, Risteys.Icd9,
      join_through: Risteys.FGEndpoint.DefinitionICD9,
      # Delete ICD-9s not included in the update
      on_replace: :delete

    timestamps()
  end

  @doc false
  def changeset(endpoint, attrs) do
    valid_upset_status = [
      "ok",
      "not run",
      "omit",
      "not enough data",
      "no data",
      "pending unroll",
      "unknown reason"
    ]

    endpoint
    |> cast(attrs, [
      :name,
      :tags,
      :level,
      :omit,
      :is_core,
      :reason_non_core,
      :selected_core_id,
      :longname,
      :sex,
      :include,
      :pre_conditions,
      :conditions,
      :control_exclude,
      :control_preconditions,
      :control_conditions,
      :outpat_icd,
      :outpat_oper,
      :hd_mainonly,
      :hd_icd_10_atc,
      :hd_icd_10,
      :hd_icd_9,
      :hd_icd_8,
      :hd_icd_10_excl,
      :hd_icd_9_excl,
      :hd_icd_8_excl,
      :cod_mainonly,
      :cod_icd_10,
      :cod_icd_9,
      :cod_icd_8,
      :cod_icd_10_excl,
      :cod_icd_9_excl,
      :cod_icd_8_excl,
      :oper_nom,
      :oper_hl,
      :oper_hp1,
      :oper_hp2,
      :kela_reimb,
      :kela_reimb_icd,
      :kela_atc_needother,
      :kela_atc,
      :kela_vnro_needother,
      :kela_vnro,
      :canc_topo,
      :canc_topo_excl,
      :canc_morph,
      :canc_morph_excl,
      :canc_behav,
      :special,
      :version,
      :parent,
      :latin,
      :category,
      :ontology,
      :description,
      :gws_hits,
      :status_upset_plot_fr,
      :status_upset_table_fr,
      :status_upset_plot_fg,
      :status_upset_table_fg,
      :fr_excl
    ])
    |> validate_required([:name])
    |> validate_inclusion(:reason_non_core, [nil, "exallc_priority", "correlated", "other"])
    |> validate_exclusion(:control_exclude, [""],
      message: "must be 'nil' instead of an empty string"
    )
    |> validate_exclusion(:control_preconditions, [""],
      message: "must be 'nil' instead of an empty string"
    )
    |> validate_exclusion(:control_conditions, [""],
      message: "must be 'nil' instead of an empty string"
    )
    |> validate_change(:ontology, fn :ontology, ontology ->
      allowed = allowed_ontology_types()

      ontology
      |> Enum.map(fn {type, _value} ->
        if type not in allowed do
          {:ontology, "#{type} not in #{inspect(allowed)}"}
        end
      end)
      |> Enum.reject(fn error -> is_nil(error) end)
    end)
    |> validate_change(:ontology, fn :ontology, ontology ->
      len = Map.get(ontology, "DOID", []) |> length()

      if len > 80 do
        [ontology: "Too many DOID: #{len} > 80"]
      else
        []
      end
    end)
    |> validate_number(:gws_hits, greater_than_or_equal_to: 0)
    |> validate_inclusion(:status_upset_plot_fr, valid_upset_status)
    |> validate_inclusion(:status_upset_table_fr, valid_upset_status)
    |> validate_inclusion(:status_upset_plot_fg, valid_upset_status)
    |> validate_inclusion(:status_upset_table_fg, valid_upset_status)
    |> unique_constraint(:name)
  end

  defp allowed_ontology_types() do
    MapSet.new([
      "DOID",
      "EFO",
      "MESH",
      "SNOMED"
    ])
  end
end
