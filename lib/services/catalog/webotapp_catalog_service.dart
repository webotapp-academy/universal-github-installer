import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class CatalogSoftware {
  final String id;
  final String name;
  final String title;
  final String description;
  final String techStack;
  final String githubUrl;
  final String category;
  final IconData icon;

  const CatalogSoftware({
    required this.id,
    required this.name,
    required this.title,
    required this.description,
    required this.techStack,
    required this.githubUrl,
    required this.category,
    this.icon = Icons.devices,
  });
}

class WebotAppCatalogService {
  static const List<CatalogSoftware> defaultCatalog = [
    CatalogSoftware(
      id: 'college-management-software',
      name: 'college-management-software',
      title: 'College Management ERP',
      category: 'Education ERP',
      techStack: 'Laravel 12 • MySQL',
      description: 'Comprehensive Indian College ERP & SIS: Admissions CRM, NEP 2020 / CBCS Academics, Timetables, Exams & CGPA, Fees, and NAAC/NIRF reporting.',
      githubUrl: 'https://github.com/webotapp-academy/college-management-software',
      icon: Icons.school,
    ),
    CatalogSoftware(
      id: 'pathology-lis',
      name: 'pathology-lis',
      title: 'Pathology Laboratory LIS',
      category: 'Healthcare / LIS',
      techStack: 'Laravel 13 • MySQL',
      description: 'NABL Diagnostic Laboratory Information System: UHID patients, barcode accession, 11 department worklists, validation, QR reports, and Levey-Jennings QC.',
      githubUrl: 'https://github.com/webotapp-academy/pathology-lis',
      icon: Icons.biotech,
    ),
    CatalogSoftware(
      id: 'jewellery-software',
      name: 'jewellery-software',
      title: 'Jewellery Showroom ERP & POS',
      category: 'Retail & POS',
      techStack: 'Laravel 13 • Tailwind • MySQL',
      description: 'Enterprise Jewellery Showroom ERP: Live metal rates, BIS HUID tracking, dynamic making charges & wastage billing, karigar job-work, and GST billing.',
      githubUrl: 'https://github.com/webotapp-academy/jewellery-software',
      icon: Icons.diamond,
    ),
    CatalogSoftware(
      id: 'special-child-therapy-center',
      name: 'special-child-therapy-center',
      title: 'Aura SpecialCare Therapy ERP',
      category: 'Special Healthcare',
      techStack: 'Laravel 12 • Tailwind • MySQL',
      description: 'Autism & Special Child Care Management System: Diagnostic assessments, IEP goals, clinical SOAP notes, daily therapy logs, and parent progress portal.',
      githubUrl: 'https://github.com/webotapp-academy/special-child-therapy-center',
      icon: Icons.child_care,
    ),
    CatalogSoftware(
      id: 'auditflow-erp',
      name: 'auditflow-erp',
      title: 'AuditFlow CA Practice ERP',
      category: 'Finance & Accounting',
      techStack: 'Laravel 13 • Bootstrap 5 • MySQL',
      description: 'Practice Management ERP for accounting professionals: Manage clients, GST, ITR, TDS, compliance deadlines, audit documents, staff tasks, and client portal.',
      githubUrl: 'https://github.com/webotapp-academy/auditflow-erp',
      icon: Icons.account_balance,
    ),
    CatalogSoftware(
      id: 'fertility-clinic-mgt-software',
      name: 'fertility-clinic-mgt-software',
      title: 'Fertility & IVF Clinic ERP',
      category: 'Healthcare / IVF',
      techStack: 'Laravel • Blade • MySQL',
      description: 'Specialized Fertility & IVF Clinic Management: Clinical stimulation protocols, cycle tracking, embryology records, and patient billing.',
      githubUrl: 'https://github.com/webotapp-academy/fertility-clinic-mgt-software',
      icon: Icons.favorite,
    ),
    CatalogSoftware(
      id: 'physio-therapy-software',
      name: 'physio-therapy-software',
      title: 'PhysioCare Clinic Management',
      category: 'Rehabilitation',
      techStack: 'Laravel • Blade • MySQL',
      description: 'Physiotherapy & Rehabilitation Clinic System: Musculoskeletal assessments, treatment plans, exercise prescriptions, and appointment billing.',
      githubUrl: 'https://github.com/webotapp-academy/physio-therapy-software',
      icon: Icons.accessibility_new,
    ),
    CatalogSoftware(
      id: 'exam-portal',
      name: 'exam-portal',
      title: 'Online Examination & Assessment Portal',
      category: 'Education & Testing',
      techStack: 'Laravel • PHP • MySQL',
      description: 'Automated Examination System: Question banks, timed exams, automated grading, performance analytics, and printable result certificates.',
      githubUrl: 'https://github.com/webotapp-academy/exam-portal',
      icon: Icons.quiz,
    ),
    CatalogSoftware(
      id: 'webotapp-pos',
      name: 'webotapp-pos',
      title: 'WebotApp Retail POS & Inventory',
      category: 'Retail POS',
      techStack: 'Flutter • Dart',
      description: 'Cross-platform Point of Sale system with offline-first billing, barcode scanning, thermal receipt printing, and real-time inventory management.',
      githubUrl: 'https://github.com/webotapp-academy/webotapp-pos',
      icon: Icons.point_of_sale,
    ),
    CatalogSoftware(
      id: 'claude-flipkart-strategy-advisor',
      name: 'claude-flipkart-strategy-advisor',
      title: 'E-Commerce Marketplace Strategy Advisor',
      category: 'E-Commerce Analytics',
      techStack: 'Python 3 • AI Insights',
      description: 'Intelligent e-commerce advisor for online sellers: Competitor price benchmarking, inventory forecasting, and marketplace growth analytics.',
      githubUrl: 'https://github.com/webotapp-academy/claude-flipkart-strategy-advisor',
      icon: Icons.insights,
    ),
  ];

  static Future<List<CatalogSoftware>> fetchCatalog() async {
    try {
      final res = await http.get(
        Uri.parse('https://api.github.com/users/webotapp-academy/repos?per_page=100&sort=updated'),
        headers: {'User-Agent': 'WebotApp-Universal-GitHub-Installer'},
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final List<dynamic> data = jsonDecode(res.body);
        final list = <CatalogSoftware>[];

        for (final item in data) {
          final name = item['name'] as String? ?? '';
          if (name.isEmpty || name == 'universal-github-installer') continue;

          // Check if we have rich metadata from defaultCatalog
          final curated = defaultCatalog.where((c) => c.name.toLowerCase() == name.toLowerCase()).firstOrNull;
          if (curated != null) {
            list.add(curated);
          } else {
            final desc = item['description'] as String? ?? 'WebotApp Academy Software Solution.';
            final lang = item['language'] as String? ?? 'Full-Stack';
            final cleanTitle = name
                .replaceAll('-', ' ')
                .replaceAll('_', ' ')
                .split(' ')
                .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
                .join(' ');

            list.add(CatalogSoftware(
              id: name,
              name: name,
              title: cleanTitle,
              category: lang.contains('PHP') || lang.contains('Blade') ? 'Laravel / PHP' : lang,
              techStack: lang,
              description: desc,
              githubUrl: item['html_url'] as String? ?? 'https://github.com/webotapp-academy/$name',
            ));
          }
        }

        // Add any remaining curated that might not have appeared in recent sort
        for (final item in defaultCatalog) {
          if (!list.any((l) => l.name.toLowerCase() == item.name.toLowerCase())) {
            list.add(item);
          }
        }

        return list;
      }
    } catch (_) {}

    return defaultCatalog;
  }
}

