import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/meeting_model.dart';
import '../services/meeting_service.dart';
import '../widgets/subject_group_list.dart';
import 'add_meeting_screen.dart';
import '../colors.dart';
import 'config_screen.dart';
import '../services/career_service.dart';

class MeetingsScreen extends StatefulWidget {
  final bool isEmbedded;
  const MeetingsScreen({super.key, this.isEmbedded = false});

  @override
  State<MeetingsScreen> createState() => _MeetingsScreenState();
}

class _MeetingsScreenState extends State<MeetingsScreen> {
  final MeetingService _meetingService = MeetingService();

  @override
  void initState() {
    super.initState();
    _meetingService.syncFromSupabase();
  }

  Future<void> _launchMeetingUrl(String url) async {
    final uri = Uri.parse(url.startsWith('http') ? url : 'https://$url');
    try {
      if (!await canLaunchUrl(uri)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se puede abrir el enlace de la reunión.')),
          );
        }
        return;
      }
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al abrir el enlace de la reunión.')),
        );
      }
    }
  }

  String _formatMeetingDate(DateTime date) {
    const days = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
    const months = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];
    final dayName = days[(date.weekday - 1) % 7];
    final monthName = months[(date.month - 1) % 12];
    final hour = date.hour.toString().padLeft(2, '0');
    final min = date.minute.toString().padLeft(2, '0');
    return '$dayName ${date.day} $monthName \u2022 $hour:$min';
  }

  @override
  Widget build(BuildContext context) {
    final career = CareerService().getSelectedCareer();
    final careerName = career?.name ?? '';

    return ListenableBuilder(
      listenable: _meetingService,
      builder: (context, _) {
        final allMeetings = _meetingService.getMeetings();

        final bodyContent = SizedBox(
          width: double.infinity,
          height: double.infinity,
          child: allMeetings.isEmpty
              ? _buildEmptyMeetingsState()
              : RefreshIndicator(
                  onRefresh: () => _meetingService.syncFromSupabase(),
                  child: SubjectGroupList<Meeting>(
                    items: allMeetings,
                    subjectOf: (m) => m.subject,
                    countLabelOf: (count) => '$count ${count == 1 ? 'reunión' : 'reuniones'}',
                    itemBuilder: _buildMeetingCard,
                  ),
                ),
        );

        if (widget.isEmbedded) {
          return bodyContent;
        }

        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('Reuniones'),
                    if (allMeetings.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${allMeetings.length}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (careerName.isNotEmpty)
                  Text(
                    careerName,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.normal,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.settings),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ConfigScreen()),
                ),
                tooltip: 'Configuración',
              ),
            ],
          ),
          body: bodyContent,
          floatingActionButton: FloatingActionButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AddMeetingScreen()),
            ),
            backgroundColor: Theme.of(context).primaryColor,
            elevation: 4,
            shape: const CircleBorder(),
            child: const Icon(Icons.add, color: Colors.white, size: 26),
          ),
        );
      },
    );
  }

  Widget _buildEmptyMeetingsState() {
    return Center(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primary.withValues(alpha: 0.15),
                      const Color(0xFF48CAE4).withValues(alpha: 0.15),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.video_camera_front_rounded,
                  size: 44,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'No tienes reuniones programadas',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Agrega tus clases virtuales (Zoom, Meet, Teams) o presenciales para mantener tus horarios al día.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getTypeColor(String type) {
    switch (type.toLowerCase()) {
      case 'zoom':
        return const Color(0xFF2D8CFF);
      case 'meet':
      case 'google meet':
        return const Color(0xFF00832D);
      case 'teams':
      case 'microsoft teams':
        return const Color(0xFF6264A7);
      case 'presencial':
        return const Color(0xFFE65100);
      default:
        return Theme.of(context).primaryColor;
    }
  }

  Widget _buildMeetingCard(Meeting meeting) {
    final effectiveType = meeting.effectiveType;
    final typeColor = _getTypeColor(effectiveType);
    final hasLink = meeting.meetingLink != null && meeting.meetingLink!.isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    meeting.typeIcon,
                    color: typeColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        meeting.title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${meeting.subject}${meeting.professor.isNotEmpty ? ' \u2022 Prof. ${meeting.professor}' : ''}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  tooltip: 'Editar',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AddMeetingScreen(meeting: meeting),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.error),
                  tooltip: 'Eliminar',
                  onPressed: () => _confirmDeleteMeeting(meeting),
                ),
              ],
            ),
            if (meeting.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                meeting.description,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 10,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.access_time_rounded, size: 15, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Text(
                      _formatMeetingDate(meeting.meetingDate),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (meeting.isRecurrent) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.purple.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Semanal',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.purple,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (hasLink)
                  FilledButton.icon(
                    onPressed: () => _launchMeetingUrl(meeting.meetingLink!),
                    icon: const Icon(Icons.video_call_rounded, size: 16),
                    label: Text('Conectarse a $effectiveType'),
                    style: FilledButton.styleFrom(
                      backgroundColor: typeColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteMeeting(Meeting meeting) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('\u00bfEliminar reuni\u00f3n?'),
        content: Text('"${meeting.title}" ser\u00e1 eliminada de tu agenda.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _meetingService.deleteMeeting(meeting.id!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reuni\u00f3n eliminada')),
        );
      }
    }
  }
}
