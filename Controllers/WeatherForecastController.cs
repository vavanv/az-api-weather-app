using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;

namespace WeatherApi.Controllers;

[ApiController]
[Route("[controller]")]
public class WeatherForecastController : ControllerBase
{
    private static readonly string[] Summaries = new[]
    {
        "Freezing", "Bracing", "Chilly", "Cool", "Mild", "Warm", "Balmy", "Hot", "Sweltering", "Scorching"
    };

    // In-memory storage (for demo purposes; use a database in production)
    private static readonly Dictionary<Guid, (WeatherForecast, DateTimeOffset)> _forecasts = new();

    private readonly ILogger<WeatherForecastController> _logger;

    public WeatherForecastController(ILogger<WeatherForecastController> logger)
    {
        _logger = logger;
    }

    /// <summary>
    /// Get all forecasts or filter by date range and temperature. Returns default Richmond Hill, Canada forecasts if empty.
    /// </summary>
    [HttpGet]
    public IActionResult Get(
        [FromQuery] DateOnly? fromDate = null,
        [FromQuery] DateOnly? toDate = null,
        [FromQuery] int? minTemp = null,
        [FromQuery] int? maxTemp = null)
    {
        // Return default Richmond Hill, Canada forecasts if storage is empty
        if (_forecasts.Count == 0)
        {
            _logger.LogInformation("No forecasts found. Returning default Richmond Hill, Canada forecasts.");
            return Ok(new[]{
                new WeatherForecast(DateOnly.FromDateTime(DateTime.Now), -5, "Freezing", "Richmond Hill, Canada"),
                new WeatherForecast(DateOnly.FromDateTime(DateTime.Now.AddDays(1)), 2, "Bracing", "Richmond Hill, Canada"),
                new WeatherForecast(DateOnly.FromDateTime(DateTime.Now.AddDays(2)), 8, "Chilly", "Richmond Hill, Canada"),
                new WeatherForecast(DateOnly.FromDateTime(DateTime.Now.AddDays(3)), 12, "Cool", "Richmond Hill, Canada"),
                new WeatherForecast(DateOnly.FromDateTime(DateTime.Now.AddDays(4)), 18, "Mild", "Richmond Hill, Canada")
            });
        }

        var forecasts = _forecasts.Values.Select(x => x.Item1).AsEnumerable();

        if (fromDate.HasValue)
            forecasts = forecasts.Where(f => f.Date >= fromDate.Value);

        if (toDate.HasValue)
            forecasts = forecasts.Where(f => f.Date <= toDate.Value);

        if (minTemp.HasValue)
            forecasts = forecasts.Where(f => f.TemperatureC >= minTemp.Value);

        if (maxTemp.HasValue)
            forecasts = forecasts.Where(f => f.TemperatureC <= maxTemp.Value);

        return Ok(forecasts.ToList());
    }

    /// <summary>
    /// Get a specific forecast by ID
    /// </summary>
    [HttpGet("{id}")]
    public IActionResult GetById(Guid id)
    {
        if (_forecasts.TryGetValue(id, out var forecast))
        {
            return Ok(new { id, forecast.Item1 });
        }
        return NotFound($"Forecast with ID {id} not found");
    }

    /// <summary>
    /// Get weather statistics
    /// </summary>
    [HttpGet("statistics/summary")]
    public IActionResult GetStatistics()
    {
        if (_forecasts.Count == 0)
            return Ok(new { message = "No forecasts available", count = 0 });

        var temps = _forecasts.Values.Select(x => x.Item1.TemperatureC).ToList();

        return Ok(new
        {
            totalForecasts = _forecasts.Count,
            averageTemp = temps.Average(),
            minTemp = temps.Min(),
            maxTemp = temps.Max(),
            summaryBreakdown = _forecasts.Values
                .GroupBy(x => x.Item1.Summary ?? "Unknown")
                .ToDictionary(g => g.Key, g => g.Count())
        });
    }

    /// <summary>
    /// Create a new forecast
    /// </summary>
    [HttpPost]
    public IActionResult CreateForecast([FromBody] WeatherForecast forecast)
    {
        var forecastId = Guid.NewGuid();
        _forecasts[forecastId] = (forecast, DateTimeOffset.UtcNow);

        _logger.LogInformation("Created forecast with ID {ForecastId}: {Summary}", forecastId, forecast.Summary);
        return CreatedAtAction(nameof(GetById), new { id = forecastId }, new { id = forecastId, forecast });
    }

    /// <summary>
    /// Update an existing forecast
    /// </summary>
    [HttpPut("{id}")]
    public IActionResult UpdateForecast(Guid id, [FromBody] WeatherForecast updatedForecast)
    {
        if (!_forecasts.ContainsKey(id))
            return NotFound($"Forecast with ID {id} not found");

        _forecasts[id] = (updatedForecast, DateTimeOffset.UtcNow);
        _logger.LogInformation("Updated forecast with ID {ForecastId}", id);

        return Ok(new { id, forecast = updatedForecast, message = "Forecast updated successfully" });
    }

    /// <summary>
    /// Delete a forecast
    /// </summary>
    [HttpDelete("{id}")]
    public IActionResult DeleteForecast(Guid id)
    {
        if (!_forecasts.ContainsKey(id))
            return NotFound($"Forecast with ID {id} not found");

        _forecasts.Remove(id);
        _logger.LogInformation("Deleted forecast with ID {ForecastId}", id);

        return Ok(new { message = "Forecast deleted successfully", id });
    }

    /// <summary>
    /// Generate sample forecasts for testing
    /// </summary>
    [HttpPost("generate-samples")]
    public IActionResult GenerateSamples([FromQuery] int count = 5)
    {
        var samples = new List<Guid>();

        for (int i = 0; i < count; i++)
        {
            var forecastId = Guid.NewGuid();
            var forecast = new WeatherForecast(
                DateOnly.FromDateTime(DateTime.Now.AddDays(i)),
                Random.Shared.Next(-20, 55),
                Summaries[Random.Shared.Next(Summaries.Length)],
                "Richmond Hill, Canada"
            );

            _forecasts[forecastId] = (forecast, DateTimeOffset.UtcNow);
            samples.Add(forecastId);
        }

        _logger.LogInformation("Generated {Count} sample forecasts", count);
        return Ok(new { message = $"Generated {count} sample forecasts", forecastIds = samples });
    }
}

public record WeatherForecast(DateOnly Date, int TemperatureC, string? Summary, string Location = "Unknown")
{
    public int TemperatureF => 32 + (int)(TemperatureC / 0.5556);
}
