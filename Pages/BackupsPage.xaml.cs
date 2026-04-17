using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using acorn.Models;
using acorn.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Windows.Storage.Pickers;
using WinRT.Interop;

namespace acorn.Pages
{
    public sealed partial class BackupsPage : Page
    {
        private AppConfig _config = null!;
        private readonly ObservableCollection<string> _folders = new();
        private readonly ObservableCollection<string> _includes = new();

        // Tracks each dynamically-created schedule card and its controls
        private record ScheduleCard(NumberBox IntervalBox, TextBox RepoBox, NumberBox CountBox, Border Card);
        private readonly List<ScheduleCard> _scheduleCards = new();

        public BackupsPage()
        {
            InitializeComponent();
        }

        protected override void OnNavigatedTo(Microsoft.UI.Xaml.Navigation.NavigationEventArgs e)
        {
            base.OnNavigatedTo(e);
            _config = ConfigService.Load();
            PopulateForm();
        }

        // ── Populate ─────────────────────────────────────────────────────────

        private void PopulateForm()
        {
            ConfigPathText.Text = ConfigService.ConfigPath;
            MasterToggle.IsOn   = _config.BackupsEnabled;

            _folders.Clear();
            foreach (var f in _config.FoldersWatched) _folders.Add(f);
            FoldersList.ItemsSource = _folders;

            _includes.Clear();
            foreach (var p in _config.IncludePatterns) _includes.Add(p);
            IncludeList.ItemsSource = _includes;

            SchedulesPanel.Children.Clear();
            _scheduleCards.Clear();
            foreach (var schedule in _config.Schedules)
                AddScheduleCard(schedule);
        }

        // ── Master toggle ────────────────────────────────────────────────────

        private void MasterToggle_Toggled(object sender, RoutedEventArgs e)
        {
            // Persisted on Apply — no immediate action needed.
        }

        // ── Dynamic schedule cards ────────────────────────────────────────────

        private void AddNewBackup_Click(object sender, RoutedEventArgs e) =>
            AddScheduleCard(new BackupSchedule { IntervalHours = 0.5, RepoFolder = "", SnapshotCount = 5 });

        private void AddScheduleCard(BackupSchedule schedule)
        {
            // Controls
            var intervalBox = new NumberBox
            {
                Header = "Interval (hours)",
                Minimum = 0.5,
                Maximum = 168,
                SmallChange = 0.5,
                LargeChange = 1,
                Value = schedule.IntervalHours,
                SpinButtonPlacementMode = NumberBoxSpinButtonPlacementMode.Compact,
                Width = 140
            };

            var repoBox = new TextBox
            {
                Header = "Repository folder",
                PlaceholderText = @"D:\Backups\my_backup",
                Text = schedule.RepoFolder
            };

            var browseBtn = new Button
            {
                Content = "Browse",
                VerticalAlignment = VerticalAlignment.Bottom
            };

            var countBox = new NumberBox
            {
                Header = "Keep snapshots",
                Minimum = 1,
                Maximum = 999,
                Value = schedule.SnapshotCount,
                SpinButtonPlacementMode = NumberBoxSpinButtonPlacementMode.Compact,
                Width = 130
            };

            var deleteBtn = new Button
            {
                Content = "Delete",
                VerticalAlignment = VerticalAlignment.Bottom
            };

            // Layout
            var grid = new Grid { ColumnSpacing = 12 };
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

            Grid.SetColumn(intervalBox, 0);
            Grid.SetColumn(repoBox, 1);
            Grid.SetColumn(browseBtn, 2);
            Grid.SetColumn(countBox, 3);
            Grid.SetColumn(deleteBtn, 4);

            grid.Children.Add(intervalBox);
            grid.Children.Add(repoBox);
            grid.Children.Add(browseBtn);
            grid.Children.Add(countBox);
            grid.Children.Add(deleteBtn);

            var card = new Border
            {
                Background    = (Brush)Application.Current.Resources["CardBackgroundFillColorDefaultBrush"],
                CornerRadius  = new CornerRadius(8),
                Padding       = new Thickness(16),
                BorderBrush   = (Brush)Application.Current.Resources["CardStrokeColorDefaultBrush"],
                BorderThickness = new Thickness(1),
                Child = grid
            };

            var entry = new ScheduleCard(intervalBox, repoBox, countBox, card);
            _scheduleCards.Add(entry);
            SchedulesPanel.Children.Add(card);

            browseBtn.Click += async (s, e) =>
            {
                var path = await PickFolder();
                if (path is not null) repoBox.Text = path;
            };

            deleteBtn.Click += (s, e) =>
            {
                _scheduleCards.Remove(entry);
                SchedulesPanel.Children.Remove(card);
            };
        }

        // ── Watched folders ──────────────────────────────────────────────────

        private async void AddFolder_Click(object sender, RoutedEventArgs e)
        {
            var picker = new FolderPicker { SuggestedStartLocation = PickerLocationId.Desktop };
            picker.FileTypeFilter.Add("*");
            InitializeWithWindow.Initialize(picker, GetHwnd());

            var folder = await picker.PickSingleFolderAsync();
            if (folder is not null && !_folders.Contains(folder.Path))
                _folders.Add(folder.Path);
        }

        private void RemoveFolder_Click(object sender, RoutedEventArgs e)
        {
            if (FoldersList.SelectedItem is string selected)
                _folders.Remove(selected);
        }

        // ── Include patterns ─────────────────────────────────────────────────

        private void AddInclude_Click(object sender, RoutedEventArgs e) => CommitNewInclude();

        private void NewIncludeBox_KeyDown(object sender, KeyRoutedEventArgs e)
        {
            if (e.Key == Windows.System.VirtualKey.Enter) CommitNewInclude();
        }

        private void CommitNewInclude()
        {
            var text = NewIncludeBox.Text.Trim();
            if (!string.IsNullOrEmpty(text) && !_includes.Contains(text))
            {
                _includes.Add(text);
                NewIncludeBox.Text = string.Empty;
            }
        }

        private void RemoveInclude_Click(object sender, RoutedEventArgs e)
        {
            if (IncludeList.SelectedItem is string selected)
                _includes.Remove(selected);
        }

        // ── Apply / Save ─────────────────────────────────────────────────────

        private void Apply_Click(object sender, RoutedEventArgs e)
        {
            CollectFormIntoConfig();
            ConfigService.Save(_config);
            TaskSchedulerService.Apply(_config);
            SaveBar.IsOpen = true;
        }

        private void CollectFormIntoConfig()
        {
            _config.BackupsEnabled  = MasterToggle.IsOn;
            _config.FoldersWatched  = _folders.ToList();
            _config.IncludePatterns = _includes.ToList();

            _config.Schedules = _scheduleCards.Select(card => new BackupSchedule
            {
                IntervalHours = double.IsNaN(card.IntervalBox.Value) ? 0.5 : card.IntervalBox.Value,
                RepoFolder    = card.RepoBox.Text.Trim(),
                SnapshotCount = double.IsNaN(card.CountBox.Value) ? 5 : (int)card.CountBox.Value,
                StartTime     = "09:00"
            }).ToList();
        }

        // ── Helpers ───────────────────────────────────────────────────────────

        private async System.Threading.Tasks.Task<string?> PickFolder()
        {
            var picker = new FolderPicker { SuggestedStartLocation = PickerLocationId.ComputerFolder };
            picker.FileTypeFilter.Add("*");
            InitializeWithWindow.Initialize(picker, GetHwnd());
            var folder = await picker.PickSingleFolderAsync();
            return folder?.Path;
        }

        private static nint GetHwnd() =>
            WindowNative.GetWindowHandle(App.MainWindow);
    }
}
