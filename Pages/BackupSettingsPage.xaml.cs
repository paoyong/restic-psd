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
    public sealed partial class BackupSettingsPage : Page
    {
        private AppConfig _config = null!;
        private readonly ObservableCollection<string> _folders = new();
        private readonly ObservableCollection<string> _includes = new();

        private record ScheduleCard(NumberBox IntervalBox, TextBox RepoBox, NumberBox CountBox, Border Card);
        private readonly List<ScheduleCard> _scheduleCards = new();

        public BackupSettingsPage()
        {
            InitializeComponent();
            _config = ConfigService.Load();
            PopulateForm();
        }

        private void PopulateForm()
        {
            ConfigPathText.Text = ConfigService.ConfigPath;
            MasterToggle.IsOn = _config.BackupsEnabled;

            _folders.Clear();
            foreach (var folder in _config.FoldersWatched)
                _folders.Add(folder);
            FoldersList.ItemsSource = _folders;

            _includes.Clear();
            foreach (var pattern in _config.IncludePatterns)
                _includes.Add(pattern);
            IncludeList.ItemsSource = _includes;

            SchedulesPanel.Children.Clear();
            _scheduleCards.Clear();
            foreach (var schedule in _config.Schedules)
                AddScheduleCard(schedule);
        }

        private void MasterToggle_Toggled(object sender, RoutedEventArgs e)
        {
        }

        private void AddNewBackup_Click(object sender, RoutedEventArgs e) =>
            AddScheduleCard(new BackupSchedule { IntervalHours = 1, RepoFolder = "", SnapshotCount = 5 });

        private void AddScheduleCard(BackupSchedule schedule)
        {
            var intervalBox = new NumberBox
            {
                Header = "Interval (hours)",
                Minimum = 1,
                Maximum = 168,
                SmallChange = 1,
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
                Background = (Brush)Application.Current.Resources["CardBackgroundFillColorDefaultBrush"],
                CornerRadius = new CornerRadius(8),
                Padding = new Thickness(16),
                BorderBrush = (Brush)Application.Current.Resources["CardStrokeColorDefaultBrush"],
                BorderThickness = new Thickness(1),
                Child = grid
            };

            var entry = new ScheduleCard(intervalBox, repoBox, countBox, card);
            _scheduleCards.Add(entry);
            SchedulesPanel.Children.Add(card);

            browseBtn.Click += async (_, _) =>
            {
                var path = await PickFolder(PickerLocationId.ComputerFolder);
                if (path is not null)
                    repoBox.Text = path;
            };

            deleteBtn.Click += (_, _) =>
            {
                _scheduleCards.Remove(entry);
                SchedulesPanel.Children.Remove(card);
            };
        }

        private async void AddFolder_Click(object sender, RoutedEventArgs e)
        {
            var folder = await PickFolder(PickerLocationId.Desktop);
            if (folder is not null && !_folders.Contains(folder))
                _folders.Add(folder);
        }

        private void RemoveFolder_Click(object sender, RoutedEventArgs e)
        {
            if (FoldersList.SelectedItem is string selected)
                _folders.Remove(selected);
        }

        private void AddInclude_Click(object sender, RoutedEventArgs e) => CommitNewInclude();

        private void NewIncludeBox_KeyDown(object sender, KeyRoutedEventArgs e)
        {
            if (e.Key == Windows.System.VirtualKey.Enter)
                CommitNewInclude();
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

        private void Apply_Click(object sender, RoutedEventArgs e)
        {
            CollectFormIntoConfig();
            ConfigService.Save(_config);
            TaskSchedulerService.Apply(_config);
            SaveBar.IsOpen = true;
        }

        private void CollectFormIntoConfig()
        {
            _config.BackupsEnabled = MasterToggle.IsOn;
            _config.FoldersWatched = _folders.ToList();
            _config.IncludePatterns = _includes.ToList();

            _config.Schedules = _scheduleCards.Select(card => new BackupSchedule
            {
                IntervalHours = Math.Max(1, (int)Math.Round(double.IsNaN(card.IntervalBox.Value) ? 1 : card.IntervalBox.Value)),
                RepoFolder = card.RepoBox.Text.Trim(),
                SnapshotCount = double.IsNaN(card.CountBox.Value) ? 5 : (int)card.CountBox.Value
            }).ToList();
        }

        private async System.Threading.Tasks.Task<string?> PickFolder(PickerLocationId startLocation)
        {
            var picker = new FolderPicker { SuggestedStartLocation = startLocation };
            picker.FileTypeFilter.Add("*");
            InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(App.MainWindow));
            var folder = await picker.PickSingleFolderAsync();
            return folder?.Path;
        }
    }
}
