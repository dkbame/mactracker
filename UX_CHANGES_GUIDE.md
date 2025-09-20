# Torrust UX Changes Guide

## Project Structure Overview

The Torrust project consists of three main components:

### 1. **Torrust Tracker** (Rust)
- **Location**: `torrust-tracker/`
- **Purpose**: BitTorrent tracker that manages peer connections
- **Configuration**: `storage/tracker/etc/tracker.toml`
- **Database**: `storage/tracker/lib/database/sqlite3.db`

### 2. **Torrust Index** (Rust)
- **Location**: `torrust-index/`
- **Purpose**: Backend API for torrent metadata management
- **Configuration**: `storage/index/etc/index.toml`
- **Database**: `storage/index/lib/database/sqlite3.db`

### 3. **Torrust Index GUI** (Vue.js/Nuxt)
- **Location**: `torrust-index-gui/`
- **Purpose**: Frontend web interface
- **Framework**: Nuxt 3 + Vue 3 + Tailwind CSS + DaisyUI

## GUI File Structure for UX Changes

### Core Files
```
torrust-index-gui/
├── app.vue                    # Main app layout
├── nuxt.config.ts            # Nuxt configuration
├── package.json              # Dependencies and scripts
├── tailwind.config.js        # Tailwind CSS configuration
└── assets/css/tailwind.css   # Global styles
```

### Pages (Route-based Components)
```
pages/
├── index.vue                 # Homepage (/)
├── upload.vue               # Upload page (/upload) ⭐
├── torrents.vue             # Torrent list (/torrents)
├── signin.vue               # Login page (/signin)
├── signup.vue               # Registration page (/signup)
├── torrent/
│   ├── [infoHash].vue       # Torrent details (/torrent/{hash})
│   └── [infoHash]/[title].vue # Torrent with title (/torrent/{hash}/{title})
└── admin/
    └── settings/            # Admin pages
```

### Components (Reusable UI Elements)
```
components/
├── navigation/
│   └── NavigationBar.vue    # Main navigation
├── torrent/
│   ├── TorrentList.vue      # Torrent listing
│   ├── TorrentDetails.vue   # Torrent details
│   ├── TorrentTrackersTab.vue # Tracker information ⭐
│   └── TorrentActionCard.vue # Action buttons
├── upload/
│   └── UploadFile.vue       # File upload component ⭐
├── form/
│   └── FormInputText.vue    # Text input component
├── TorrustButton.vue        # Custom button component
└── TorrustSelect.vue        # Custom select component
```

### Composables (Logic & State)
```
composables/
├── states.ts                # Global state management
├── helpers.ts               # Utility functions
└── useFetchForTextFiles.ts  # File fetching logic
```

## Making UX Changes

### 1. **Upload Page Changes** (Our Tracker URL Display)

**File**: `torrust-index-gui/pages/upload.vue`

**Current Structure**:
- Form with title, description, category, tags
- File upload component
- Terms agreement checkbox
- Submit button

**To Add Tracker URLs Display**:
```vue
<!-- Add this after the UploadFile component -->
<div class="p-4 bg-base-200/50 rounded-2xl border border-base-content/10">
  <h3 class="text-lg font-semibold text-neutral-content mb-3">Tracker URLs</h3>
  <p class="text-sm text-neutral-content/70 mb-3">Your torrent will use these tracker URLs:</p>
  <div class="space-y-2">
    <div class="flex items-center gap-3">
      <span class="text-xs font-medium text-primary uppercase tracking-wide">UDP:</span>
      <code class="flex-1 p-2 bg-base-100 rounded-lg text-sm font-mono text-neutral-content border border-base-content/20">
        udp://macosapps.net:6969/announce
      </code>
    </div>
    <div class="flex items-center gap-3">
      <span class="text-xs font-medium text-secondary uppercase tracking-wide">HTTP:</span>
      <code class="flex-1 p-2 bg-base-100 rounded-lg text-sm font-mono text-neutral-content border border-base-content/20">
        http://macosapps.net:7070/announce
      </code>
    </div>
  </div>
  <p class="text-xs text-neutral-content/50 mt-2">
    These URLs will be embedded in your torrent file for peer discovery.
  </p>
</div>
```

### 2. **Development vs Production**

#### **Development Mode** (Source Files)
```bash
cd torrust-index-gui
npm run dev  # Runs on http://localhost:3000
```
- Changes to `.vue` files are reflected immediately
- Hot reload enabled
- Source maps available

#### **Production Mode** (Compiled Files)
```bash
cd torrust-index-gui
npm run build  # Creates .output/ directory
npm run preview  # Serves built files
```
- Files are compiled to JavaScript bundles
- No source files in container
- Requires rebuild for changes

### 3. **Styling System**

**Framework**: Tailwind CSS + DaisyUI

**Key Classes**:
- `bg-base-200/50` - Background colors
- `text-neutral-content` - Text colors
- `rounded-2xl` - Border radius
- `border border-base-content/10` - Borders
- `p-4`, `m-3` - Padding/margins
- `flex`, `gap-3` - Layout

**Color System**:
- `primary` - Primary brand color
- `secondary` - Secondary brand color
- `base-content` - Text content color
- `neutral-content` - Neutral text color

### 4. **Configuration Files**

#### **Nuxt Config** (`nuxt.config.ts`)
```typescript
export default defineNuxtConfig({
  ssr: false,  // Client-side rendering
  modules: [
    "@nuxtjs/tailwindcss",
    "@nuxtjs/color-mode"
  ],
  runtimeConfig: {
    public: {
      apiBase: process.env.API_BASE_URL
    }
  }
})
```

#### **Environment Variables** (`.env`)
```
API_BASE_URL=http://localhost:3001
NUXT_PUBLIC_API_BASE=https://macosapps.net/api/v1
```

## Deployment Strategies

### 1. **Development Changes**
1. Edit source files in `torrust-index-gui/`
2. Run `npm run dev`
3. Changes appear immediately

### 2. **Production Changes** (Docker)
1. Edit source files
2. Rebuild container: `docker build -t torrust-gui .`
3. Restart container: `docker compose restart torrust-gui`

### 3. **Runtime Changes** (Our Approach)
1. Modify compiled files in container
2. Add custom CSS/JS files
3. Restart container to apply changes

## Common UX Change Patterns

### 1. **Adding Information Displays**
- Create styled information boxes
- Use consistent spacing and colors
- Add icons for visual hierarchy

### 2. **Form Enhancements**
- Add help text and descriptions
- Include validation messages
- Show required field indicators

### 3. **Navigation Changes**
- Modify `NavigationBar.vue`
- Update routes in `pages/` directory
- Add breadcrumbs if needed

### 4. **Theme Customization**
- Modify `tailwind.config.js`
- Update DaisyUI theme settings
- Add custom CSS in `assets/css/`

## Best Practices

1. **Consistent Styling**: Use DaisyUI components and Tailwind classes
2. **Responsive Design**: Test on mobile and desktop
3. **Accessibility**: Include proper ARIA labels and semantic HTML
4. **Performance**: Minimize bundle size, use lazy loading
5. **Testing**: Use Cypress for E2E testing

## Debugging Tips

1. **Browser DevTools**: Inspect elements and check console
2. **Nuxt DevTools**: Available in development mode
3. **Container Logs**: `docker logs torrust-gui`
4. **Network Tab**: Check API calls and responses

## Next Steps for Tracker URL Display

Since we're using a production Docker deployment, we have two options:

### Option 1: Source Code Changes (Recommended)
1. Clone the GUI repository locally
2. Make changes to `pages/upload.vue`
3. Rebuild and redeploy the container

### Option 2: Runtime Injection (Current Approach)
1. Continue with JavaScript injection
2. Add custom CSS/JS files to container
3. Modify HTML templates at runtime

The source code approach is more maintainable and reliable for long-term changes.
