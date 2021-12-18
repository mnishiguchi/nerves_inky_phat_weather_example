defmodule InkyPhatWeather.Core do
  @moduledoc false

  defstruct ~w[chisel_font inky_pid last_weather icons]a

  @icon_names ~w[cloud rain snow storm sun wind]
  @default_icons_dir "/my_app/icons"
  @default_icon_offset {200, 80}

  # Build a map of icon name to Inky-compatible pixels based on icon pixel data
  def init_icons!(opts \\ []) do
    @icon_names
    |> Enum.map(fn icon_name -> init_icon!(icon_name, opts) end)
    |> Enum.into(%{})
  end

  defp init_icon!(icon_name, opts) do
    {icon_offset_x, icon_offset_y} = Access.get(opts, :icon_offset, @default_icon_offset)
    icons_dir = Access.get(opts, :icons_dir, @default_icons_dir)

    {
      icon_name,
      File.read!("#{icons_dir}/#{icon_name}.json")
      |> Jason.decode!()
      |> Enum.with_index()
      |> Enum.flat_map(fn {row, index_y} ->
        row
        |> Enum.with_index()
        |> Enum.map(fn
          {0, index_x} -> {{index_x + icon_offset_x, index_y + icon_offset_y}, :white}
          {_, index_x} -> {{index_x + icon_offset_x, index_y + icon_offset_y}, :black}
        end)
      end)
      |> Enum.into(%{})
    }
  end

  def refresh_pixels!(state) do
    state = maybe_fetch_and_assign_weather(state)

    clear_pixels(state)
    maybe_set_weather_pixels(state)
    set_current_time_pixels(state)
    maybe_set_icon(state)
    push_pixels(state)

    state
  end

  defp set_current_time_pixels(state) do
    NaiveDateTime.local_now()
    |> Calendar.strftime("%Y-%m-%d %I:%M %p")
    |> print_text({10, 10}, :black, [size_x: 2, size_y: 3], state)
  end

  defp maybe_fetch_and_assign_weather(state) do
    # Fetch every 30 minutes
    if is_nil(state.last_weather) or DateTime.utc_now().minute in [0, 30] do
      %{state | last_weather: InkyPhatWeather.Weather.get_current_weather()}
    else
      state
    end
  end

  defp maybe_set_weather_pixels(%{last_weather: nil} = _state), do: :ignore

  defp maybe_set_weather_pixels(%{last_weather: last_weather} = state) do
    %{"weatherDesc" => weather_desc, "FeelsLikeF" => feel_like_f} = last_weather

    """
    #{weather_desc}
    Feels like #{feel_like_f}°
    """
    |> print_text({10, 64}, :black, [size_x: 2, size_y: 2], state)
  end

  defp maybe_set_icon(%{last_weather: nil} = _state), do: :ignore

  defp maybe_set_icon(%{last_weather: last_weather} = state) do
    %{"weatherDesc" => weather_desc} = last_weather

    icon_name = InkyPhatWeather.Weather.get_icon_name(weather_desc)

    if icon_name do
      Inky.set_pixels(state.inky_pid, Access.fetch!(state.icons, icon_name), push: :skip)
    end
  end

  defp clear_pixels(state) do
    Inky.set_pixels(state.inky_pid, fn _x, _y, _w, _h, _pixels -> :white end, push: :skip)
  end

  defp print_text(text, {x, y}, color, opts, state) do
    put_pixels_fun = fn x, y ->
      Inky.set_pixels(state.inky_pid, %{{x, y} => color}, push: :skip)
    end

    Chisel.Renderer.draw_text(text, x, y, state.chisel_font, put_pixels_fun, opts)
  end

  defp push_pixels(state) do
    Inky.set_pixels(state.inky_pid, %{}, push: :await)
  end
end
