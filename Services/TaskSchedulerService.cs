using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using acorn.Models;
using Windows.Storage;

namespace acorn.Services
{
    public static class TaskSchedulerService
    {
        private static readonly string ScriptsFolder =
            Path.Combine(ApplicationData.Current.LocalFolder.Path, "Scripts");

        public static void Apply(AppConfig config)
        {
            Directory.CreateDirectory(ScriptsFolder);

            RemoveTrackedTasks();
            RemoveGeneratedScripts();

            if (!config.BackupsEnabled) return;

            var configKey = ResticCommandScriptBuilder.BuildConfigKey(ConfigService.ConfigPath);
            var configScriptsFolder = Path.Combine(ScriptsFolder, configKey);
            Directory.CreateDirectory(configScriptsFolder);

            for (int i = 0; i < config.Schedules.Count; i++)
            {
                var schedule = config.Schedules[i];
                if (string.IsNullOrWhiteSpace(schedule.RepoFolder)) continue;

                var taskName = BuildTaskName(configKey, schedule, i);
                var scriptPath = GenerateScript(config, schedule, configScriptsFolder, i);
                RegisterHourlyTask(taskName, scriptPath, schedule.IntervalHours);
            }
        }

        private static string GenerateScript(AppConfig config, BackupSchedule schedule, string configScriptsFolder, int index)
        {
            var path = Path.Combine(configScriptsFolder, $"backup_task_{index}_{schedule.IntervalHours}_hours.bat");
            var keyFile = Path.Combine(configScriptsFolder, "restic.key");
            var scriptContent = ResticCommandScriptBuilder.BuildBatchScript(config, schedule, keyFile);

            File.WriteAllText(path, scriptContent);
            return path;
        }

        private static void Schtasks(string args)
        {
            using var p = Process.Start(new ProcessStartInfo("schtasks.exe", args)
            {
                CreateNoWindow = true,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            });
            p?.WaitForExit();
        }

        private static void RemoveTrackedTasks()
        {
            using var p = Process.Start(new ProcessStartInfo("schtasks.exe", "/query /fo csv /nh")
            {
                CreateNoWindow = true,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            });

            var output = p?.StandardOutput.ReadToEnd() ?? string.Empty;
            p?.WaitForExit();

            var taskNames = output
                .Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries)
                .Select(line => line.Split(',').FirstOrDefault()?.Trim('"'))
                .Where(name => !string.IsNullOrWhiteSpace(name) && name.StartsWith("Acorn\\Backup_", StringComparison.OrdinalIgnoreCase))
                .Distinct(StringComparer.OrdinalIgnoreCase);

            foreach (var taskName in taskNames)
                RemoveTask(taskName!);
        }

        private static void RemoveGeneratedScripts()
        {
            if (!Directory.Exists(ScriptsFolder))
                return;

            foreach (var directory in Directory.GetDirectories(ScriptsFolder))
                Directory.Delete(directory, true);
        }

        private static string BuildTaskName(string configKey, BackupSchedule schedule, int index) =>
            $"Acorn\\Backup_{configKey}_{schedule.IntervalHours}_hours_{index}";

        private static void RegisterHourlyTask(string name, string scriptPath, int hours)
        {
            RemoveTask(name);
            Schtasks($"/create /tn \"{name}\" /tr \"\\\"{scriptPath}\\\"\" /sc hourly /mo {Math.Max(1, hours)} /f");
        }

        public static void RemoveTask(string name) =>
            Schtasks($"/delete /tn \"{name}\" /f");
    }
}
