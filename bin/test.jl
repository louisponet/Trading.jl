using Trading
using Statistics
using Stipple, StippleUI, StipplePlotly

# TODO make this a form
const account = AccountInfo("PKJJPKQDXIKDPRSRWV8H", "FPDmXPCfnpJTwvOCL5HO3nQlM5721g1esu0qa1Fu") 

@reactive mutable struct DashBoard <: ReactiveModel
    symbol::R{String} = "AAPL"
    timeframe::R{String} = "1Min"
    start_date::R{String} = "2022-03-14T13:30:00" 
    stop_date::R{String} = "2022-03-14T20:10:00"
    bars::R{Vector{Bar}} = Bar[]
    plot_data::R{PlotData} = PlotData()
    plot_layout::R{PlotLayout} = PlotLayout(showlegend = false)
end

function fill_bars!(m::DashBoard)
    m.bars[] = Trading.query_bars(account, m.symbol[], Trading.TimeDate(m.start_date[]), stop=Trading.TimeDate(m.stop_date[]), timeframe=m.timeframe[])
end

function plot_model(m::DashBoard)
    tids = 1:10:length(m.bars[])
    times = map(x-> Dates.format(DateTime(Hour(x.time), Minute(x.time)), "HH:MM"), m.bars[][tids])
    m.plot_data[] = PlotData(x = 1:length(m.bars[]),
                             y = map(x->mean((x.open, x.close)), m.bars[]),
                             )
end

function create_model(m::DashBoard)
    fill_bars!(m)
    plot_model(m)
    return m
end

dash_model = create_model(DashBoard()) |> init

on(dash_model.symbol) do _
    fill_bars!(dash_model)
end
on(dash_model.timeframe) do _
    fill_bars!(dash_model)
end
on(dash_model.start_date) do _
    fill_bars!(dash_model)
end
on(dash_model.stop_date) do _
    fill_bars!(dash_model)
end
on(dash_model.bars) do _
    plot_model(dash_model)
end
    
function ui(model)
  page(model, 
  title="Test", 
  head_content = Genie.Assets.favicon_support(), 
  partial = false,
  prepend = style(
    """
    .modebar {
      display: none!important;
    }
    """
  ),
  [
    input(
          "",
          placeholder="Ticker",
          @bind(:symbol)
    ), 
    cell(class="st-module", [plot(:plot_data, layout = :plot_layout, config = "{ displayLogo:false }")])
  ]
  )
end

route("/") do
    ui(dash_model) |> html
end
up()
dash_model.symbol[]
down()
