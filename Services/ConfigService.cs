using System;
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;
using acorn.Models;
using Windows.Storage;

namespace acorn.Services
{
    public static class ConfigService
    {
        public static readonly string ConfigPath = Path.Combine(
            ApplicationData.Current.LocalFolder.Path,
            "config.json");

        private static readonly JsonSerializerOptions Options = new()
        {
            WriteIndented = true,
            PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
            DefaultIgnoreCondition = JsonIgnoreCondition.Never
        };

        public static AppConfig Load()
        {
            if (!File.Exists(ConfigPath))
            {
                var defaults = CreateDefaults();
                Save(defaults);
                return defaults;
            }

            try
            {
                var json = File.ReadAllText(ConfigPath);
                return JsonSerializer.Deserialize<AppConfig>(json, Options) ?? CreateDefaults();
            }
            catch
            {
                return CreateDefaults();
            }
        }

        public static void Save(AppConfig config)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(ConfigPath)!);
            File.WriteAllText(ConfigPath, JsonSerializer.Serialize(config, Options));
        }

        private static AppConfig CreateDefaults() => new()
        {
            BackupsEnabled = true,
            FoldersWatched = new() { Environment.GetFolderPath(Environment.SpecialFolder.Desktop) },
            IncludePatterns = new() { "*WORKING*" },
            ExcludePatterns = new() { "*.tmp", "*.log", "Thumbs.db" },
            Schedules = new()   // empty — user adds their own
        };
    }
}
