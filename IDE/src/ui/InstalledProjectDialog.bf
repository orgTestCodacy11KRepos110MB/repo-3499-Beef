using Beefy.theme.dark;
using Beefy.widgets;
using Beefy.events;
using System;
using System.Collections;
using Beefy.gfx;
using IDE.Util;
using System.IO;

namespace IDE.ui
{
	class InstalledProjectDialog : IDEDialog
	{
		class InstalledProject
		{
			public String mName ~ delete _;
			public String mPath ~ delete _;
			public VerSpecRecord mVersion;
			public Project.TargetType mTargetType;
		}

		protected IDEListView mProjectList;
		DarkComboBox mKindCombo;
		EditWidget mEditWidget;
		bool mFilterChanged;
		List<InstalledProject> mInstalledProjectList = new .() ~ DeleteContainerAndItems!(_);
		List<InstalledProject> mFilteredList = new .() ~ delete _;
		public static Dictionary<String, int32> sMRU = new .() ~
		{
			for (let key in _.Keys)
				delete key;
			delete _;
		};

		public this()
		{
		    mWindowFlags = .ClientSized | .TopMost | .Caption | .Border | .SysMenu | .Resizable | .PopupPosition;

		    AddOkCancelButtons(new (evt) => { DoImport(); }, null, 0, 1);
		    //mApplyButton = AddButton("Apply", (evt) => { evt.mCloseDialog = false; ApplyChanges(); });
		    
		    Title = "Import Installed Project";

		    mButtonBottomMargin = GS!(6);
		    mButtonRightMargin = GS!(6);

		    mProjectList = new .();            
		    mProjectList.InitScrollbars(false, true);
		    mProjectList.mAllowMultiSelect = false;
			mProjectList.mOnItemMouseDown.Add(new => ValueMouseDown);

		    ListViewColumn column = mProjectList.AddColumn(GS!(200), "Project");
		    column.mMinWidth = GS!(100);
		    column = mProjectList.AddColumn(GS!(200), "Path");

		    AddWidget(mProjectList);
		    mTabWidgets.Add(mProjectList);

		    mEditWidget = AddEdit("");
		    mEditWidget.mOnKeyDown.Add(new => EditKeyDownHandler);
		    mEditWidget.mOnContentChanged.Add(new (evt) => { mFilterChanged = true; });

			mKindCombo = new DarkComboBox();
			mKindCombo.Label = "Libraries";
			mKindCombo.mPopulateMenuAction.Add(new (menu) =>
				{
					for (var kind in String[?]("All", "Libraries"))
					{
						menu.AddItem(kind).mOnMenuItemSelected.Add(new (menu) =>
							{
								mFilterChanged = true;
								mKindCombo.Label = kind;
							});
					}
				});
			AddWidget(mKindCombo);

			FindProjects();
		}

		void FindProjects()
		{
			gApp.CheckLoadConfig();
			gApp.mBeefConfig.mRegistry.WaitFor();
			for (let registryEntry in gApp.mBeefConfig.mRegistry.mEntries)
			{
				InstalledProject installedProject = new .();
				installedProject.mName = new String(registryEntry.mProjName);
				switch (registryEntry.mLocation)
				{
				case .Path(let path):
					installedProject.mPath = new String();
					Path.GetAbsolutePath(path, registryEntry.mConfigFile.mConfigDir, installedProject.mPath);
					installedProject.mPath.Append(Path.DirectorySeparatorChar);
					installedProject.mPath.Append("BeefProj.toml");
				default:
				}
				installedProject.mTargetType = registryEntry.mTargetType;
				mInstalledProjectList.Add(installedProject);
			}
		}

		void EditKeyDownHandler(KeyDownEvent evt)
		{
			switch (evt.mKeyCode)
			{
			case .Up,
				 .Down,
				 .PageUp,
				 .PageDown:
				mProjectList.KeyDown(evt.mKeyCode, false);
			default:
			}

			if (evt.mKeyFlags == .Ctrl)
			{
				switch (evt.mKeyCode)
				{
				case .Home,
					 .End:
					mProjectList.KeyDown(evt.mKeyCode, false);
				default:
				}
			}
		}

		public void ValueMouseDown(ListViewItem clickedItem, float x, float y, int32 btnNum, int32 btnCount)
		{
		    DarkListViewItem item = (DarkListViewItem)clickedItem.GetSubItem(0);

		    mProjectList.GetRoot().SelectItemExclusively(item);
		    mProjectList.SetFocus();

		    if ((btnNum == 0) && (btnCount > 1))
		    {
		        DoImport();
		    }
		}

		void FilterFiles()
		{
			let root = mProjectList.GetRoot();
			root.Clear();

		    String filterString = scope String();
		    mEditWidget.GetText(filterString);
		    filterString.Trim();

			bool onlyLibs = mKindCombo.Label == "Libraries";

			mFilteredList.Clear();
		    for (var installedProject in mInstalledProjectList)
		    {
				if ((onlyLibs) && (!installedProject.mTargetType.IsLib))
					continue;

				if ((!filterString.IsEmpty) && (installedProject.mName.IndexOf(filterString, true) == -1))
					continue;

		        var listViewItem = mProjectList.GetRoot().CreateChildItem();
		        listViewItem.Label = installedProject.mName;

		        var subListViewItem = listViewItem.CreateSubItem(1);
		        subListViewItem.Label = Path.GetDirectoryPath(installedProject.mPath, .. scope .());

				mFilteredList.Add(installedProject);
		    }

		    ListViewItem bestItem = null;
		    int32 bestPri = -1;
		    for (int32 childIdx = 0; childIdx < root.GetChildCount(); childIdx++)
		    {
		        var listViewItem = root.GetChildAtIndex(childIdx);
		        var projectSource = mFilteredList[childIdx];

		        int32 pri;
		        sMRU.TryGetValue(projectSource.mPath, out pri);
		        if (pri > bestPri)
		        {
		            bestItem = listViewItem;
		            bestPri = pri;
		        }
		    }

		    if (bestItem != null)
		    {
		        mProjectList.GetRoot().SelectItemExclusively(bestItem);                
		        mProjectList.EnsureItemVisible(bestItem, true);
		    }
		}

		public void DoImport()
		{
			let root = mProjectList.GetRoot();
			for (int idx < root.GetChildCount())
			{
				let listViewItem = root.GetChildAtIndex(idx);
				if (!listViewItem.Selected)
					continue;

				let entry = mFilteredList[idx];

				VerSpec verSpec = .SemVer(new .("*"));
				defer verSpec.Dispose();

				let project = gApp.mProjectPanel.ImportProject(entry.mPath, null, verSpec);
				if (project == null)
				{
					return;
				}
				if (project.mProjectName != entry.mName)
				{
					gApp.OutputLineSmart("WARNING: Project directory name '{}' does not match project name '{}' specified in '{}'.\n Project will be referenced by relative path rather than by name.", entry.mName, project.mProjectName, project.mProjectPath);

					String relProjectPath = scope .();
					Path.GetRelativePath(project.mProjectDir, gApp.mWorkspace.mDir, relProjectPath);
					for (var projectSpec in gApp.mWorkspace.mProjectSpecs)
					{
						if (projectSpec.mProjectName == project.mProjectName)
						{
							projectSpec.mVerSpec = .Path(new String(relProjectPath));
						}
					}
				}
				project.mLocked = true;
				project.mLockedDefault = true;
			}

			Close();
		}

		public override void AddedToParent()
		{
		    base.AddedToParent();
		    mEditWidget.SetFocus();

		    FilterFiles();
		}

		public override void ResizeComponents()
		{
		    base.ResizeComponents();
		    
		    //var font = DarkTheme.sDarkTheme.mSmallFont;

			float insetSize = GS!(6);
		    mProjectList.Resize(insetSize, insetSize, mWidth - insetSize - insetSize, mHeight - GS!(66));
		    mEditWidget.Resize(insetSize, mProjectList.mY + mProjectList.mHeight + insetSize, mWidth - insetSize - insetSize, GS!(22));
			mKindCombo.Resize(insetSize, mHeight - GS!(26), Math.Min(GS!(160), mDefaultButton.mX - GS!(6)), GS!(26));
		}

		public override void CalcSize()
		{
		    mWidth = GS!(660);
		    mHeight = GS!(512);
		}

		public override void Resize(float x, float y, float width, float height)
		{
		    base.Resize(x, y, width, height);
		    ResizeComponents();
		}

		public override void DrawAll(Graphics g)
		{
		    base.DrawAll(g);
			IDEUtils.DrawOutline(g, mProjectList);
		}

		public override void Update()
		{
		    base.Update();

		    if (mFilterChanged)
		    {
		        FilterFiles();
		        mFilterChanged = false;
		    }
		}
	}
}
