using System.Collections.Generic;

namespace acorn.Models
{
    public class BackupSchedule
    {
        public double IntervalHours { get; set; } = 0.5;   // e.g. 0.5 = every 30 min, 24 = every day
        public string RepoFolder { get; set; } = "";
        public int SnapshotCount { get; set; } = 5;
        public string StartTime { get; set; } = "09:00";   // HH:mm — used as daily run time or first-run anchor
    }

    public class AppConfig
    {
        public bool BackupsEnabled { get; set; } = true;
        public List<string> FoldersWatched { get; set; } = new();
        public List<string> IncludePatterns { get; set; } = new() { "*WORKING*" };
        public List<string> ExcludePatterns { get; set; } = new() { "*.tmp", "*.log", "Thumbs.db" };
        public List<BackupSchedule> Schedules { get; set; } = new();
    }
}
